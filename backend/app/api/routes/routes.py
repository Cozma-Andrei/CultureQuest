from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_db
from app.models.route import RouteRequest, RouteResponse, RouteWithProgress, ReorderPayload
from app.services.route_service import generate_cultural_route, get_user_routes, get_global_routes, reorder_route_stops

router = APIRouter()


@router.get("/global", response_model=list[RouteWithProgress])
async def global_routes(db=Depends(get_db)):
    return await get_global_routes(db)


@router.post("/generate", response_model=RouteResponse)
async def generate_route(payload: RouteRequest, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await generate_cultural_route(db, user_id, payload)


