import math
from datetime import datetime
from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from fastapi import HTTPException, status

from app.models.route import RouteRequest, RouteResponse, RouteStop, RouteWithProgress, RouteStopWithProgress, ReorderPayload
from app.models.landmark import LandmarkResponse
from app.services.landmark_service import get_nearby_landmarks, get_landmark_by_id
from app.services.auth_service import get_user_by_id

_WALKING_M_PER_MIN = 83   # ~5 km/h
_VISIT_MINUTES = 25       # default

_INTERESTS = ['art', 'architecture', 'history', 'gastronomy', 'nature', 'music']
_TYPES     = ['museum', 'monument', 'park', 'gallery', 'restaurant', 'square', 'building', 'other']

def _build_feature_vector(
    user_interests: list[str],
    landmark: LandmarkResponse,
    stop_index: int,
    total_stops: int,
    relative_distance_rank: float,
) -> list[float]:
    now = datetime.now()
    is_weekend = now.weekday() >= 5
    v = [0.0] * 22
    for i, interest in enumerate(_INTERESTS):
        if interest in user_interests:
            v[i] = 1.0
    type_idx = _TYPES.index(landmark.type) if landmark.type in _TYPES else len(_TYPES) - 1
    v[6 + type_idx] = 1.0
    v[14] = 1.0  # assume open during planning
    v[15] = 1.0 if is_weekend else 0.0
    v[16] = now.hour / 24.0
    v[17] = relative_distance_rank
    if user_interests:
        matches = sum(1 for c in landmark.categories if c in user_interests)
        v[18] = matches / len(user_interests)
    v[19] = 1.0  # is part of route
    v[20] = (stop_index / (total_stops - 1)) if total_stops > 1 else 0.0
    v[21] = ((total_stops - 1) / 4.0) if total_stops > 0 else 0.0
    return v

# Realistic dwell time by landmark type
_VISIT_MINUTES_BY_TYPE: dict[str, int] = {
    "museum":     70,
    "gallery":    45,
    "restaurant": 50,
    "park":       35,
    "building":   25,
    "monument":   20,
    "square":     15,
}


def _haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def _score(landmark: LandmarkResponse, user_interests: list[str], origin_lat: float, origin_lng: float, max_dist: float) -> float:
    interest_score = sum(1 for c in landmark.categories if c in user_interests) / max(len(landmark.categories), 1)
    dist = _haversine(origin_lat, origin_lng, landmark.location.lat, landmark.location.lng)
    dist_score = 1.0 - min(dist / max_dist, 1.0)
    return interest_score * 0.6 + dist_score * 0.4


async def generate_cultural_route(db: AsyncIOMotorDatabase, user_id: str, request: RouteRequest, redis=None) -> RouteResponse:
    user = await get_user_by_id(db, user_id)
    user_interests = [i.value for i in user.interests]

    nearby = await get_nearby_landmarks(db, request.start_location.lat, request.start_location.lng, 10000)
    if not nearby:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No landmarks found nearby. Try seeding sample data first.")

    # Load FL weights first: needed for both candidate scoring and tiebreaking.
    fl_weights = None
    if redis is not None:
        try:
            from app.services.fl_service import get_global_weights
            from app.federated.model import fl_predict
            _, fl_weights = await get_global_weights(redis)
        except Exception:
            fl_weights = None

    # Distances from start for all nearby landmarks.
    nearby_dists = {
        l.id: _haversine(request.start_location.lat, request.start_location.lng, l.location.lat, l.location.lng)
        for l in nearby
    }
    max_nearby_dist = max(nearby_dists.values()) if nearby_dists else 1.0

    # Step 1: score every nearby landmark to pick the best candidates.
    # FL score (route dims = 0) replaces the hand-crafted interest match because it
    # already encodes user interests, landmark type, and interest-match fraction via
    # the feature vector. Fallback to hand-crafted _score if no FL weights.
    all_fl_scores: dict[str, float] = {}
    if fl_weights is not None:
        for l in nearby:
            dist_rank = nearby_dists[l.id] / max_nearby_dist
            fv = _build_feature_vector(user_interests, l, 0, 0, dist_rank)
            all_fl_scores[l.id] = fl_predict(fl_weights, fv)

    def _initial_score(l: LandmarkResponse) -> float:
        dist_score = 1.0 - min(nearby_dists[l.id] / 2000, 1.0)
        if l.id in all_fl_scores:
            return all_fl_scores[l.id] * 0.8 + dist_score * 0.2
        interest_score = sum(1 for c in l.categories if c in user_interests) / max(len(l.categories), 1)
        return interest_score * 0.8 + dist_score * 0.2

    candidates = sorted(nearby, key=_initial_score, reverse=True)[:request.max_landmarks * 2]

    candidate_dists = {l.id: nearby_dists[l.id] for l in candidates}
    max_dist = max(candidate_dists.values()) if candidate_dists else 1.0

    # Step 2 (tiebreaker): reuse FL scores from step 1, normalised so the full
    # tiebreaker window is in play regardless of how compressed the raw scores are.
    _TIEBREAKER_M = request.fl_tiebreaker_m
    fl_scores = {l.id: all_fl_scores[l.id] for l in candidates if l.id in all_fl_scores}
    fl_norm: dict[str, float] = {}
    if fl_scores:
        lo, hi = min(fl_scores.values()), max(fl_scores.values())
        spread = hi - lo
        for lid, s in fl_scores.items():
            fl_norm[lid] = (s - lo) / spread if spread > 1e-6 else 0.5

    def _interest_match(l: LandmarkResponse) -> float:
        if not user_interests:
            return 0.0
        return sum(1 for c in l.categories if c in user_interests) / max(len(l.categories), 1)

    def _selection_key(l: LandmarkResponse, cur_lat: float, cur_lng: float) -> float:
        dist = _haversine(cur_lat, cur_lng, l.location.lat, l.location.lng)
        return dist - _TIEBREAKER_M * _interest_match(l)

    # Greedy nearest-neighbour route building with FL tiebreaker.
    stops: list[tuple[LandmarkResponse, int, float]] = []
    cur_lat, cur_lng = request.start_location.lat, request.start_location.lng
    remaining = list(candidates)
    total_visit_minutes = 0
    total_walk_minutes = 0.0

    while remaining and len(stops) < request.max_landmarks:
        nearest = min(remaining, key=lambda l: _selection_key(l, cur_lat, cur_lng))
        remaining.remove(nearest)
        walk = _haversine(cur_lat, cur_lng, nearest.location.lat, nearest.location.lng) / _WALKING_M_PER_MIN
        visit = _VISIT_MINUTES_BY_TYPE.get(nearest.type, _VISIT_MINUTES)
        if total_visit_minutes + visit > request.available_minutes:
            break
        stops.append((nearest, visit, round(all_fl_scores.get(nearest.id, 0.0), 2)))
        total_visit_minutes += visit
        total_walk_minutes += walk
        cur_lat, cur_lng = nearest.location.lat, nearest.location.lng

    if not stops and candidates:
        l = candidates[0]
        visit = _VISIT_MINUTES_BY_TYPE.get(l.type, _VISIT_MINUTES)
        stops = [(l, visit, round(all_fl_scores.get(l.id, 0.0), 2))]
        total_visit_minutes = visit

    # FL dwell scaling: score in [0,1] maps to multiplier [0.75, 1.25].
    total_stops = len(stops)
    scaled_stops: list[tuple[LandmarkResponse, int, float]] = []
    scaled_total_visit = 0
    for i, (landmark, base_visit, rel_score) in enumerate(stops):
        if fl_weights is not None:
            dist_rank = candidate_dists.get(landmark.id, 0.0) / max_dist
            fv = _build_feature_vector(user_interests, landmark, i, total_stops, dist_rank)
            fl_score = fl_predict(fl_weights, fv)
            scaled_visit = max(5, round(base_visit * (0.75 + 0.5 * fl_score)))
        else:
            scaled_visit = base_visit
        scaled_stops.append((landmark, scaled_visit, rel_score))
        scaled_total_visit += scaled_visit

    total_dist = 0.0
    prev_lat, prev_lng = request.start_location.lat, request.start_location.lng
    for landmark, _, _ in scaled_stops:
        total_dist += _haversine(prev_lat, prev_lng, landmark.location.lat, landmark.location.lng)
        prev_lat, prev_lng = landmark.location.lat, landmark.location.lng

    import uuid
    return RouteResponse(
        id=str(uuid.uuid4()),
        stops=[RouteStop(landmark=l, estimated_duration_minutes=d, relevance_score=s) for l, d, s in scaled_stops],
        total_distance_m=round(total_dist),
        total_duration_minutes=scaled_total_visit + int(total_walk_minutes),
        generated_at=datetime.utcnow().isoformat(),
    )


async def get_global_routes(db: AsyncIOMotorDatabase) -> list[RouteWithProgress]:
    """Return all routes marked global (curated/admin routes visible to everyone)."""
    docs = await db.routes.find({"is_global": True}).sort("name", 1).to_list(None)

    all_stop_ids: set[str] = set()
    for doc in docs:
        all_stop_ids.update(doc.get("stop_ids", []))

    routes: list[RouteWithProgress] = []
    for doc in docs:
        stop_ids = doc.get("stop_ids", [])
        dwell_list = doc.get("dwell_minutes", [])
        stops: list[RouteStopWithProgress] = []
        for i, lid in enumerate(stop_ids):
            landmark = await get_landmark_by_id(db, lid)
            if landmark:
                dwell = dwell_list[i] if i < len(dwell_list) else 25
                stops.append(RouteStopWithProgress(landmark=landmark, visited=False, dwell_minutes=dwell))
        routes.append(RouteWithProgress(
            id=str(doc["_id"]),
            name=doc.get("name"),
            stops=stops,
            total_distance_m=doc.get("total_distance_m", 0),
            total_duration_minutes=doc.get("total_duration_minutes", 0),
            generated_at=doc.get("generated_at", ""),
            visited_count=0,
            is_global=True,
        ))
    return routes


async def get_user_routes(db: AsyncIOMotorDatabase, user_id: str) -> list[RouteWithProgress]:
    docs = await db.routes.find({"user_id": user_id}).sort("generated_at", -1).to_list(None)

    # Collect all stop_ids across all routes for a single visited lookup
    all_stop_ids: set[str] = set()
    for doc in docs:
        all_stop_ids.update(doc.get("stop_ids", []))

    visited_ids: set[str] = set()
    if all_stop_ids:
        async for v in db.visits.find({"user_id": user_id, "landmark_id": {"$in": list(all_stop_ids)}}):
            visited_ids.add(v["landmark_id"])

    routes: list[RouteWithProgress] = []
    for doc in docs:
        stop_ids = doc.get("stop_ids", [])
        stops: list[RouteStopWithProgress] = []
        for lid in stop_ids:
            landmark = await get_landmark_by_id(db, lid)
            if landmark:
                stops.append(RouteStopWithProgress(landmark=landmark, visited=lid in visited_ids))
        routes.append(RouteWithProgress(
            id=str(doc["_id"]),
            name=doc.get("name"),
            stops=stops,
            total_distance_m=doc.get("total_distance_m", 0),
            total_duration_minutes=doc.get("total_duration_minutes", 0),
            generated_at=doc.get("generated_at", ""),
            visited_count=sum(1 for s in stops if s.visited),
        ))
    return routes


async def reorder_route_stops(
    db: AsyncIOMotorDatabase, route_id: str, user_id: str, payload: ReorderPayload
) -> RouteWithProgress | None:
    try:
        oid = ObjectId(route_id)
    except InvalidId:
        return None
    doc = await db.routes.find_one({"_id": oid, "user_id": user_id})
    if not doc:
        return None
    current_ids = set(doc.get("stop_ids", []))
    # Keep only IDs that actually belong to this route, in the requested order
    new_ids = [sid for sid in payload.stop_ids if sid in current_ids]
    await db.routes.update_one({"_id": oid}, {"$set": {"stop_ids": new_ids}})
    # Return the updated route with progress
    updated = await db.routes.find_one({"_id": oid})
    visited_ids: set[str] = set()
    async for v in db.visits.find({"user_id": user_id, "landmark_id": {"$in": new_ids}}):
        visited_ids.add(v["landmark_id"])
    stops: list[RouteStopWithProgress] = []
    for lid in new_ids:
        landmark = await get_landmark_by_id(db, lid)
        if landmark:
            stops.append(RouteStopWithProgress(landmark=landmark, visited=lid in visited_ids))
    return RouteWithProgress(
        id=route_id,
        name=updated.get("name"),
        stops=stops,
        total_distance_m=updated.get("total_distance_m", 0),
        total_duration_minutes=updated.get("total_duration_minutes", 0),
        generated_at=updated.get("generated_at", ""),
        visited_count=sum(1 for s in stops if s.visited),
    )
