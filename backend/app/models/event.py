from pydantic import BaseModel
from typing import Optional


class EventCreate(BaseModel):
    title: str
    description: str
    start_time: str   # ISO 8601 e.g. "2026-06-15T18:00:00"
    end_time: Optional[str] = None


class EventUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None


class EventResponse(BaseModel):
    id: str
    landmark_id: str
    landmark_name: Optional[str] = None
    title: str
    description: str
    start_time: str
    end_time: Optional[str] = None
    is_upcoming: bool = False
    is_ongoing: bool = False
    created_by: Optional[str] = None
