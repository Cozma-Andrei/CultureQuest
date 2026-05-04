from fastapi import APIRouter, Depends
from app.api.deps import get_db
from app.models.user import UserCreate, UserLogin, TokenResponse

router = APIRouter()


@router.post("/register", response_model=TokenResponse)
async def register(payload: UserCreate, db=Depends(get_db)):
    pass


@router.post("/login", response_model=TokenResponse)
async def login(payload: UserLogin, db=Depends(get_db)):
    pass


@router.get("/me")
async def me(db=Depends(get_db)):
    pass
