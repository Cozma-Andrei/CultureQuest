from pydantic import BaseModel
from typing import Optional
from enum import Enum


class LandmarkType(str, Enum):
    museum = "museum"
    monument = "monument"
    park = "park"
    building = "building"
    square = "square"
    restaurant = "restaurant"
    gallery = "gallery"


class GeoPoint(BaseModel):
    lat: float
    lng: float


class LandmarkCreate(BaseModel):
    name: str
    type: LandmarkType
    location: GeoPoint
    description: str
    categories: list[str] = []
    stories: list[str] = []


class LandmarkResponse(LandmarkCreate):
    id: str
    rating: float = 0.0
    visit_count: int = 0
    has_active_quest: bool = False
    visited_by_me: bool = False


class RatingPayload(BaseModel):
    rating: int  # 1–5
