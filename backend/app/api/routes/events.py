from fastapi import APIRouter, Depends, HTTPException
from app.api.deps import get_current_user, get_db
from app.models.event import EventCreate, EventResponse
from app.services.event_service import (
    create_event, get_events_for_landmark, get_nearby_events, delete_event,
)

router = APIRouter()


@router.post("/", response_model=EventResponse, status_code=201)
async def add_event(
    landmark_id: str,
    payload: EventCreate,
    user_id: str = Depends(get_current_user),
    db=Depends(get_db),
):
    result = await create_event(db, landmark_id, user_id, payload)
    if not result:
        raise HTTPException(status_code=404, detail="Landmark not found")
    return result


@router.get("/landmark/{landmark_id}", response_model=list[EventResponse])
async def events_for_landmark(landmark_id: str, db=Depends(get_db)):
    return await get_events_for_landmark(db, landmark_id)


@router.get("/nearby", response_model=list[EventResponse])
async def nearby_events(lat: float, lng: float, radius_m: int = 2000, db=Depends(get_db)):
    return await get_nearby_events(db, lat, lng, radius_m)


@router.delete("/{event_id}", status_code=204)
async def remove_event(
    event_id: str,
    user_id: str = Depends(get_current_user),
    db=Depends(get_db),
):
    ok = await delete_event(db, event_id, user_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Event not found")
