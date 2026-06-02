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


async def generate_cultural_route(db: AsyncIOMotorDatabase, user_id: str, request: RouteRequest) -> RouteResponse:
    user = await get_user_by_id(db, user_id)
    user_interests = [i.value for i in user.interests]

    nearby = await get_nearby_landmarks(db, request.start_location.lat, request.start_location.lng, 10000)
    if not nearby:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No landmarks found nearby. Try seeding sample data first.")

    scored = sorted(nearby, key=lambda l: _score(l, user_interests, request.start_location.lat, request.start_location.lng, 2000), reverse=True)
    candidates = scored[:request.max_landmarks * 2]

    # Greedy nearest-neighbour route building.
    # Budget only counts time AT landmarks (visit time); walking time is informational.
    stops: list[tuple[LandmarkResponse, int, float]] = []
    cur_lat, cur_lng = request.start_location.lat, request.start_location.lng
    remaining = list(candidates)
    total_visit_minutes = 0

    while remaining and len(stops) < request.max_landmarks:
        nearest = min(remaining, key=lambda l: _haversine(cur_lat, cur_lng, l.location.lat, l.location.lng))
        remaining.remove(nearest)
        walk = _haversine(cur_lat, cur_lng, nearest.location.lat, nearest.location.lng) / _WALKING_M_PER_MIN
        visit = _VISIT_MINUTES_BY_TYPE.get(nearest.type, _VISIT_MINUTES)
        if total_visit_minutes + visit > request.available_minutes:
            break
        stop_total = int(walk + visit)  # walking + visit, shown per stop
        stops.append((nearest, stop_total, round(_score(nearest, user_interests, request.start_location.lat, request.start_location.lng, 2000), 2)))
        total_visit_minutes += visit
        cur_lat, cur_lng = nearest.location.lat, nearest.location.lng

    if not stops and candidates:
        l = candidates[0]
        visit = _VISIT_MINUTES_BY_TYPE.get(l.type, _VISIT_MINUTES)
        stops = [(l, visit, round(_score(l, user_interests, request.start_location.lat, request.start_location.lng, 2000), 2))]
        total_visit_minutes = visit

    total_dist = 0.0
    prev_lat, prev_lng = request.start_location.lat, request.start_location.lng
    for landmark, _, _ in stops:
        total_dist += _haversine(prev_lat, prev_lng, landmark.location.lat, landmark.location.lng)
        prev_lat, prev_lng = landmark.location.lat, landmark.location.lng

    generated_at = datetime.utcnow().isoformat()
    # Route is returned to the client for local storage — not persisted server-side
    import uuid
    return RouteResponse(
        id=str(uuid.uuid4()),
        stops=[RouteStop(landmark=l, estimated_duration_minutes=d, relevance_score=s) for l, d, s in stops],
        total_distance_m=round(total_dist),
        total_duration_minutes=sum(d for _, d, _ in stops),  # sum of (walk+visit) per stop
        generated_at=generated_at,
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
