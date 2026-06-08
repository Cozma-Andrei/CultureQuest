from datetime import datetime, timezone
from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from fastapi import HTTPException

from app.models.event import EventCreate, EventResponse


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _classify(doc: dict) -> tuple[bool, bool]:
    """Returns (is_upcoming, is_ongoing)."""
    try:
        start = datetime.fromisoformat(doc["start_time"])
        end_str = doc.get("end_time")
        end = datetime.fromisoformat(end_str) if end_str else None
        now = _now()
        if start > now:
            return True, False
        if end and end > now:
            return False, True
        if not end and start <= now:
            # No end time: treat as ongoing for 24 h after start
            from datetime import timedelta
            return False, (now - start).total_seconds() < 86400
    except Exception:
        pass
    return False, False


def _doc_to_event(doc: dict, landmark_name: str | None = None) -> EventResponse:
    is_upcoming, is_ongoing = _classify(doc)
    return EventResponse(
        id=str(doc["_id"]),
        landmark_id=doc["landmark_id"],
        landmark_name=landmark_name or doc.get("landmark_name"),
        title=doc["title"],
        description=doc["description"],
        start_time=doc["start_time"],
        end_time=doc.get("end_time"),
        is_upcoming=is_upcoming,
        is_ongoing=is_ongoing,
        created_by=doc.get("created_by"),
    )


async def _can_create(db: AsyncIOMotorDatabase, user_id: str, landmark_id: str) -> bool:
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    if user and user.get("is_admin"):
        return True
    try:
        lm = await db.landmarks.find_one({"_id": ObjectId(landmark_id)})
        return lm and lm.get("submitted_by") == user_id
    except Exception:
        return False


async def create_event(
    db: AsyncIOMotorDatabase, landmark_id: str, user_id: str, payload: EventCreate
) -> EventResponse | None:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    lm = await db.landmarks.find_one({"_id": oid})
    if not lm:
        return None
    if not await _can_create(db, user_id, landmark_id):
        raise HTTPException(status_code=403, detail="Only admins or the landmark submitter can create events")
    doc = {
        "landmark_id": landmark_id,
        "title": payload.title,
        "description": payload.description,
        "start_time": payload.start_time,
        "end_time": payload.end_time,
        "created_by": user_id,
    }
    result = await db.events.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _doc_to_event(doc, landmark_name=lm.get("name"))


async def get_events_for_landmark(
    db: AsyncIOMotorDatabase, landmark_id: str
) -> list[EventResponse]:
    """Returns upcoming and ongoing events for a landmark, sorted by start_time."""
    try:
        lm = await db.landmarks.find_one({"_id": ObjectId(landmark_id)}, {"name": 1})
    except Exception:
        lm = None
    lm_name = lm.get("name") if lm else None

    # Fetch all events for this landmark, then filter in Python (avoids ISO string comparison issues)
    docs = await db.events.find({"landmark_id": landmark_id}).sort("start_time", 1).to_list(None)
    results = []
    for doc in docs:
        upcoming, ongoing = _classify(doc)
        if upcoming or ongoing:
            results.append(_doc_to_event(doc, lm_name))
    return results


async def get_nearby_events(
    db: AsyncIOMotorDatabase, lat: float, lng: float, radius_m: int = 2000
) -> list[EventResponse]:
    """Returns upcoming/ongoing events for landmarks within radius_m metres."""
    cursor = db.landmarks.find({
        "location": {
            "$nearSphere": {
                "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                "$maxDistance": radius_m,
            }
        }
    }).limit(50)
    nearby = await cursor.to_list(50)
    if not nearby:
        return []

    lm_names = {str(lm["_id"]): lm.get("name", "") for lm in nearby}
    lm_ids = list(lm_names.keys())

    docs = await db.events.find({"landmark_id": {"$in": lm_ids}}).sort("start_time", 1).to_list(None)
    results = []
    for doc in docs:
        upcoming, ongoing = _classify(doc)
        if upcoming or ongoing:
            results.append(_doc_to_event(doc, lm_names.get(doc["landmark_id"])))
    return results


async def delete_event(db: AsyncIOMotorDatabase, event_id: str, user_id: str) -> bool:
    try:
        oid = ObjectId(event_id)
    except InvalidId:
        return False
    doc = await db.events.find_one({"_id": oid})
    if not doc:
        return False
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    is_admin = user.get("is_admin", False) if user else False
    if not is_admin and doc.get("created_by") != user_id:
        raise HTTPException(status_code=403, detail="Not authorised to delete this event")
    result = await db.events.delete_one({"_id": oid})
    return result.deleted_count > 0
