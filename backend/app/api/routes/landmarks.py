from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_optional_user, get_db
from app.models.landmark import LandmarkCreate, LandmarkResponse, RatingPayload
from app.services.landmark_service import (
    get_nearby_landmarks, get_all_landmarks, get_landmark_by_id, create_landmark,
    seed_landmarks, record_visit, rate_landmark,
)

router = APIRouter()


@router.get("/", response_model=list[LandmarkResponse])
async def list_landmarks(lat: float, lng: float, radius_m: int = 1500, user_id=Depends(get_optional_user), db=Depends(get_db)):
    return await get_nearby_landmarks(db, lat, lng, radius_m, user_id=user_id)


@router.get("/all", response_model=list[LandmarkResponse])
async def list_all_landmarks(user_id=Depends(get_optional_user), db=Depends(get_db)):
    return await get_all_landmarks(db, user_id=user_id)


@router.get("/{landmark_id}", response_model=LandmarkResponse)
async def get_landmark(landmark_id: str, db=Depends(get_db)):
    landmark = await get_landmark_by_id(db, landmark_id)
    if not landmark:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return landmark


@router.post("/", response_model=LandmarkResponse)
async def add_landmark(payload: LandmarkCreate, user=Depends(get_current_user), db=Depends(get_db)):
    return await create_landmark(db, payload)


@router.post("/seed", response_model=list[LandmarkResponse])
async def seed(lat: float, lng: float, db=Depends(get_db)):
    """Dev endpoint: insert sample landmarks around the given coordinate."""
    return await seed_landmarks(db, lat, lng)


@router.post("/{landmark_id}/visit", status_code=204)
async def visit(landmark_id: str, user_id=Depends(get_current_user), db=Depends(get_db)):
    await record_visit(db, landmark_id, user_id)


@router.post("/{landmark_id}/rate", response_model=LandmarkResponse)
async def rate(landmark_id: str, payload: RatingPayload, user_id=Depends(get_current_user), db=Depends(get_db)):
    if not (1 <= payload.rating <= 5):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Rating must be 1–5")
    result = await rate_landmark(db, landmark_id, user_id, payload.rating)
    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return result
