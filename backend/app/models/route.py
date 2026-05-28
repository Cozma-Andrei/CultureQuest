from pydantic import BaseModel
from app.models.landmark import LandmarkResponse, GeoPoint


class RouteRequest(BaseModel):
    start_location: GeoPoint
    interests: list[str]
    available_minutes: int
    max_landmarks: int = 5


class RouteStop(BaseModel):
    landmark: LandmarkResponse
    estimated_duration_minutes: int
    relevance_score: float


class RouteResponse(BaseModel):
    id: str
    stops: list[RouteStop]
    total_distance_m: float
    total_duration_minutes: int
    generated_at: str


class RouteStopWithProgress(BaseModel):
    landmark: LandmarkResponse
    visited: bool = False


class RouteWithProgress(BaseModel):
    id: str
    name: str | None = None
    stops: list[RouteStopWithProgress]
    total_distance_m: float
    total_duration_minutes: int
    generated_at: str
    visited_count: int = 0
