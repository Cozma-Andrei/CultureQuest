import math
from datetime import datetime
from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_admin_user, get_db
from app.models.route import RouteRequest, RouteResponse, RouteWithProgress, ReorderPayload, AdminRouteCreate
from app.services.route_service import generate_cultural_route, get_user_routes, get_global_routes, reorder_route_stops
from app.services.landmark_service import get_landmark_by_id

router = APIRouter()


@router.get("/global", response_model=list[RouteWithProgress])
async def global_routes(db=Depends(get_db)):
    return await get_global_routes(db)


def _haversine(lat1, lng1, lat2, lng2):
    R = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin(math.radians(lat2-lat1)/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(math.radians(lng2-lng1)/2)**2
    return 2*R*math.asin(math.sqrt(a))


@router.post("/admin", response_model=RouteWithProgress, status_code=201)
async def create_admin_route(
    payload: AdminRouteCreate,
    admin_id: str = Depends(get_admin_user),
    db=Depends(get_db),
):
    if len(payload.stop_ids) < 2:
        raise HTTPException(status_code=422, detail="A route needs at least 2 stops")
    stops = []
    prev_lat, prev_lng = None, None
    total_dist = 0.0
    for lid in payload.stop_ids:
        lm = await get_landmark_by_id(db, lid)
        if not lm:
            raise HTTPException(status_code=404, detail=f"Landmark {lid} not found")
        if prev_lat is not None:
            total_dist += _haversine(prev_lat, prev_lng, lm.location.lat, lm.location.lng)
        prev_lat, prev_lng = lm.location.lat, lm.location.lng
        stops.append(lm)
    # Dwell times: use provided list, pad/trim to match stop count, default 30 min
    dwell_list = payload.dwell_minutes or []
    dwell_minutes = [(dwell_list[i] if i < len(dwell_list) else 25) for i in range(len(stops))]
    total_dwell = sum(dwell_minutes)
    walking_min = int(total_dist / 83)
    total_min = walking_min + total_dwell
    generated_at = datetime.utcnow().isoformat()
    result = await db.routes.insert_one({
        "user_id": admin_id,
        "is_global": True,
        "name": payload.name.strip(),
        "stop_ids": payload.stop_ids,
        "dwell_minutes": dwell_minutes,
        "total_distance_m": round(total_dist),
        "total_duration_minutes": total_min,
        "generated_at": generated_at,
    })
    from app.services.route_service import RouteStopWithProgress, RouteWithProgress as RWP
    return RWP(
        id=str(result.inserted_id),
        name=payload.name.strip(),
        stops=[RouteStopWithProgress(landmark=lm, visited=False, dwell_minutes=dwell_minutes[i])
               for i, lm in enumerate(stops)],
        total_distance_m=round(total_dist),
        total_duration_minutes=total_min,
        generated_at=generated_at,
        visited_count=0,
        is_global=True,
    )


@router.post("/generate", response_model=RouteResponse)
async def generate_route(payload: RouteRequest, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await generate_cultural_route(db, user_id, payload)


