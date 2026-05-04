from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.landmark import LandmarkCreate, LandmarkResponse

router = APIRouter()


@router.get("/", response_model=list[LandmarkResponse])
async def list_landmarks(lat: float, lng: float, radius_m: int = 500, db=Depends(get_db)):
    pass


@router.get("/{landmark_id}", response_model=LandmarkResponse)
async def get_landmark(landmark_id: str, db=Depends(get_db)):
    pass


@router.post("/", response_model=LandmarkResponse)
async def create_landmark(payload: LandmarkCreate, user=Depends(get_current_user), db=Depends(get_db)):
    pass
