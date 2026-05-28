from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.route import RouteRequest, RouteResponse, RouteWithProgress
from app.services.route_service import generate_cultural_route, get_user_routes

router = APIRouter()


@router.post("/generate", response_model=RouteResponse)
async def generate_route(payload: RouteRequest, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await generate_cultural_route(db, user_id, payload)


@router.get("/history/me", response_model=list[RouteWithProgress])
async def my_routes(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await get_user_routes(db, user_id)
