from pydantic import BaseModel
from app.models.landmark import LandmarkResponse, GeoPoint


class RouteRequest(BaseModel):
    start_location: GeoPoint
    interests: list[str]
    available_minutes: int
    max_landmarks: int = 5
    fl_tiebreaker_m: float = 200.0


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
    dwell_minutes: int = 25  # time to spend at this stop (excluding travel), matches _VISIT_MINUTES


class RouteWithProgress(BaseModel):
    id: str
    name: str | None = None
    stops: list[RouteStopWithProgress]
    total_distance_m: float
    total_duration_minutes: int
    generated_at: str
    visited_count: int = 0
    is_global: bool = False


class ReorderPayload(BaseModel):
    stop_ids: list[str]


class AdminRouteCreate(BaseModel):
    name: str
    stop_ids: list[str]
    dwell_minutes: list[int] = []  # per-stop dwell time; defaults to 30 min each if omitted
