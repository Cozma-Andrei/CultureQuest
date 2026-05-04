from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.route import RouteRequest, RouteResponse

router = APIRouter()


@router.post("/generate", response_model=RouteResponse)
async def generate_route(payload: RouteRequest, user=Depends(get_current_user), db=Depends(get_db)):
    pass


@router.get("/{route_id}", response_model=RouteResponse)
async def get_route(route_id: str, user=Depends(get_current_user), db=Depends(get_db)):
    pass


@router.get("/history/me", response_model=list[RouteResponse])
async def my_routes(user=Depends(get_current_user), db=Depends(get_db)):
    pass
