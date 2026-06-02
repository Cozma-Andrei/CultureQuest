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
    website: str | None = None
    opening_hours: str | None = None


class LandmarkStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class LandmarkResponse(LandmarkCreate):
    id: str
    rating: float = 0.0
    visit_count: int = 0
    has_active_quest: bool = False
    status: LandmarkStatus = LandmarkStatus.approved
    submitted_by: str | None = None
    # website inherited from LandmarkCreate


class LandmarkSubmit(BaseModel):
    name: str
    type: LandmarkType
    location: GeoPoint
    description: str
    categories: list[str] = []


class LandmarkEdit(BaseModel):
    name: str | None = None
    type: LandmarkType | None = None
    description: str | None = None
    categories: list[str] | None = None
    website: str | None = None
    opening_hours: str | None = None


class StorySubmit(BaseModel):
    text: str


class StoryResponse(BaseModel):
    id: str
    landmark_id: str
    landmark_name: str | None = None
    text: str
    status: str = "pending"
    submitted_by: str | None = None


class RatingPayload(BaseModel):
    rating: int           # 1–5 new value
    previous_rating: int | None = None  # user's previous rating from local storage
