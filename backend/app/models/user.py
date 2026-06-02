from pydantic import BaseModel, EmailStr
from typing import Optional
from enum import Enum


class InterestCategory(str, Enum):
    art = "art"
    architecture = "architecture"
    history = "history"
    gastronomy = "gastronomy"
    nature = "nature"
    music = "music"


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    name: str
    interests: list[InterestCategory] = []


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserProfile(BaseModel):
    id: str
    email: EmailStr
    name: str
    interests: list[InterestCategory]
    points: int = 0
    completed_quests: int = 0
    is_admin: bool = False


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserProfile


class LocationUpdate(BaseModel):
    lat: float
    lng: float


class NearbyUser(BaseModel):
    user_id: str
    display_name: str
    distance_m: float


class ModelUpdate(BaseModel):
    round: int
    weights: list[list[float]]
    num_samples: int
