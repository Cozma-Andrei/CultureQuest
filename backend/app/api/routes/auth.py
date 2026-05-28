from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.user import UserCreate, UserLogin, TokenResponse, UserProfile, InterestCategory
from app.services.auth_service import register_user, login_user, get_user_by_id, update_interests
from pydantic import BaseModel

router = APIRouter()


class InterestsUpdate(BaseModel):
    interests: list[InterestCategory]


@router.post("/register", response_model=TokenResponse)
async def register(payload: UserCreate, db=Depends(get_db)):
    return await register_user(db, payload)


@router.post("/login", response_model=TokenResponse)
async def login(payload: UserLogin, db=Depends(get_db)):
    return await login_user(db, payload)


@router.get("/me", response_model=UserProfile)
async def me(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await get_user_by_id(db, user_id)


@router.patch("/interests", response_model=UserProfile)
async def set_interests(payload: InterestsUpdate, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await update_interests(db, user_id, payload.interests)
