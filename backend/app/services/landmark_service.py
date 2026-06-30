from datetime import datetime, timedelta
from bson import ObjectId
from bson.errors import InvalidId
from fastapi import HTTPException
from motor.motor_asyncio import AsyncIOMotorDatabase
from app.models.landmark import LandmarkCreate, LandmarkResponse, GeoPoint, LandmarkType, LandmarkSubmit, LandmarkEdit, LandmarkStatus, StorySubmit, StoryResponse
from app.services.quest_service import seed_quests_for_landmark

_MAX_STORIES = 5
_MAX_QUESTS = 5

_NEARBY_TEST_REVIEWS = [
    ("Absolutely loved this spot! The history here is palpable.", 5),
    ("Great place to stop and reflect. Really peaceful atmosphere.", 5),
    ("Interesting landmark, though a bit hard to find at first.", 4),
    ("Nice addition to the city tour. The story behind it is fascinating.", 4),
    ("Visited on a rainy day — still worth it. Well-maintained.", 4),
    ("A hidden gem in the city. Brought my kids and they loved it.", 5),
    ("Decent spot, nothing too spectacular but informative.", 3),
    ("The surroundings could use some cleanup, but the landmark itself is charming.", 3),
    ("Came here twice already. Always something new to notice.", 5),
    ("Good location for a quick visit. Would recommend to tourists.", 4),
]


def _doc_to_landmark(doc: dict) -> LandmarkResponse:
    coords = doc["location"]["coordinates"]  # GeoJSON stores [lng, lat]
    return LandmarkResponse(
        id=str(doc["_id"]),
        name=doc["name"],
        type=doc["type"],
        location=GeoPoint(lat=coords[1], lng=coords[0]),
        description=doc["description"],
        categories=doc.get("categories", []),
        stories=doc.get("stories", []),
        website=doc.get("website"),
        opening_hours=doc.get("opening_hours"),
        ticket_price=doc.get("ticket_price"),
        discount_info=doc.get("discount_info"),
        rating=doc.get("rating", 0.0),
        visit_count=doc.get("visit_count", 0),
        has_active_quest=doc.get("has_active_quest", False),
        status=doc.get("status", LandmarkStatus.approved),
        submitted_by=doc.get("submitted_by"),
    )


async def get_nearby_landmarks(
    db: AsyncIOMotorDatabase, lat: float, lng: float, radius_m: int, user_id: str | None = None
) -> list[LandmarkResponse]:
    cursor = db.landmarks.find({
        "status": {"$in": ["approved", None]},
        "location": {
            "$nearSphere": {
                "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                "$maxDistance": radius_m,
            }
        }
    }).limit(50)
    docs = await cursor.to_list(50)
    return [_doc_to_landmark(doc) for doc in docs]


async def get_all_landmarks(
    db: AsyncIOMotorDatabase, user_id: str | None = None
) -> list[LandmarkResponse]:
    docs = await db.landmarks.find({"status": {"$in": ["approved", None]}}).to_list(None)
    return [_doc_to_landmark(doc) for doc in docs]


async def get_landmark_by_id(db: AsyncIOMotorDatabase, landmark_id: str) -> LandmarkResponse | None:
    try:
        doc = await db.landmarks.find_one({"_id": ObjectId(landmark_id)})
    except InvalidId:
        return None
    return _doc_to_landmark(doc) if doc else None


async def create_landmark(db: AsyncIOMotorDatabase, payload: LandmarkCreate) -> LandmarkResponse:
    doc = {
        "name": payload.name,
        "type": payload.type.value,
        "location": {
            "type": "Point",
            "coordinates": [payload.location.lng, payload.location.lat],
        },
        "description": payload.description,
        "categories": payload.categories,
        "stories": payload.stories,
        "rating": 0.0,
        "visit_count": 0,
        "has_active_quest": False,
    }
    result = await db.landmarks.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _doc_to_landmark(doc)


async def record_visit(db: AsyncIOMotorDatabase, landmark_id: str) -> None:
    """Anonymously increment visit_count. No user identity stored."""
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return
    await db.landmarks.update_one({"_id": oid}, {"$inc": {"visit_count": 1}})


async def rate_landmark(
    db: AsyncIOMotorDatabase, landmark_id: str, rating: int, previous_rating: int | None = None
) -> LandmarkResponse | None:
    """Update aggregate rating using sum/count: no per-user record stored."""
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    if previous_rating is None:
        # First-time rating: add to sum, increment count
        await db.landmarks.update_one(
            {"_id": oid},
            {"$inc": {"rating_sum": rating, "rating_count": 1}},
        )
    else:
        # Re-rating: adjust sum, count stays the same
        await db.landmarks.update_one(
            {"_id": oid},
            {"$inc": {"rating_sum": rating - previous_rating}},
        )
    doc = await db.landmarks.find_one({"_id": oid}, {"rating_sum": 1, "rating_count": 1})
    if doc:
        r_sum = doc.get("rating_sum", rating)
        r_count = doc.get("rating_count", 1)
        avg = round(r_sum / max(r_count, 1), 2)
        await db.landmarks.update_one({"_id": oid}, {"$set": {"rating": avg}})
    return await get_landmark_by_id(db, landmark_id)


async def seed_landmarks(db: AsyncIOMotorDatabase, center_lat: float, center_lng: float, user_id: str | None = None) -> list[LandmarkResponse]:
    """Insert sample landmarks around a coordinate for development/testing."""
    samples = [
        dict(name="Nearby Test Spot", type=LandmarkType.monument, offset=(0.0003, 0.0002),
             categories=["history"], description="A proximity test landmark placed ~30 m from seed origin.",
             stories=["This spot marks where the first settlers lit a fire to signal safe passage through the valley."]),
        dict(name="City Art Museum", type=LandmarkType.museum, offset=(0.003, 0.002),
             categories=["art"], description="A beautiful museum showcasing local and international art collections.",
             stories=["The museum was founded in 1892 by local merchants who wanted to bring culture to the city."]),
        dict(name="Central Monument", type=LandmarkType.monument, offset=(-0.002, 0.004),
             categories=["history", "architecture"], description="A historic monument commemorating the city founders.",
             stories=["Built in 1900 to celebrate the centenary of the city's establishment."]),
        dict(name="City Park", type=LandmarkType.park, offset=(0.004, -0.003),
             categories=["nature"], description="A large green park perfect for a relaxing stroll.",
             stories=[]),
        dict(name="Old Town Square", type=LandmarkType.square, offset=(-0.003, -0.002),
             categories=["history", "architecture"], description="The historic main square surrounded by baroque buildings.",
             stories=["For centuries this square has been the heart of civic life."]),
        dict(name="Contemporary Gallery", type=LandmarkType.gallery, offset=(0.002, 0.005),
             categories=["art"], description="Modern art gallery with rotating exhibitions.",
             stories=[]),
        dict(name="Traditional Restaurant", type=LandmarkType.restaurant, offset=(-0.004, 0.003),
             categories=["gastronomy"], description="Traditional local cuisine prepared with fresh regional ingredients.",
             stories=["The recipe for the signature dish has been passed down for five generations."]),
        dict(name="Historic Cathedral", type=LandmarkType.building, offset=(0.005, 0.001),
             categories=["architecture", "history"], description="A stunning cathedral dating back to the 15th century.",
             stories=["Construction began in 1423 and took nearly 80 years to complete."]),
        dict(name="Music Conservatory", type=LandmarkType.building, offset=(-0.001, -0.005),
             categories=["music", "architecture"], description="Prestigious music school with regular public concerts.",
             stories=["Founded by a renowned composer in 1870, it has produced many famous alumni."]),
    ]

    # Clear existing seed data to avoid duplicates
    await db.landmarks.delete_many({"seeded": True})
    await db.quests.delete_many({"seeded": True})
    await db.comments.delete_many({"seeded": True})

    created = []
    for s in samples:
        payload = LandmarkCreate(
            name=s["name"],
            type=s["type"],
            location=GeoPoint(lat=center_lat + s["offset"][0], lng=center_lng + s["offset"][1]),
            description=s["description"],
            categories=s["categories"],
            stories=s["stories"],
        )
        doc = {
            "name": payload.name,
            "type": payload.type.value,
            "location": {
                "type": "Point",
                "coordinates": [payload.location.lng, payload.location.lat],
            },
            "description": payload.description,
            "categories": payload.categories,
            "stories": payload.stories,
            "rating": 0.0,
            "visit_count": 0,
            "has_active_quest": True,
            "seeded": True,
            "submitted_by": user_id,
            "status": "approved",
        }
        result = await db.landmarks.insert_one(doc)
        doc["_id"] = result.inserted_id
        landmark = _doc_to_landmark(doc)
        created.append(landmark)
        await seed_quests_for_landmark(db, landmark.id, landmark.name)

        if s["name"] == "Nearby Test Spot":
            now = datetime.utcnow()
            for i, (text, rating) in enumerate(_NEARBY_TEST_REVIEWS):
                await db.comments.insert_one({
                    "landmark_id": landmark.id,
                    "text": text,
                    "rating": rating,
                    "created_at": (now - timedelta(days=len(_NEARBY_TEST_REVIEWS) - i)).isoformat(),
                    "flagged": False,
                    "seeded": True,
                })

    return created


async def submit_landmark(
    db: AsyncIOMotorDatabase, payload: LandmarkSubmit, user_id: str
) -> LandmarkResponse:
    doc = {
        "name": payload.name,
        "type": payload.type.value,
        "location": {"type": "Point", "coordinates": [payload.location.lng, payload.location.lat]},
        "description": payload.description,
        "categories": payload.categories,
        "stories": [],
        "rating": 0.0,
        "visit_count": 0,
        "has_active_quest": False,
        "status": LandmarkStatus.pending,
        "submitted_by": user_id,
    }
    result = await db.landmarks.insert_one(doc)
    doc["_id"] = result.inserted_id
    return _doc_to_landmark(doc)


async def get_pending_landmarks(db: AsyncIOMotorDatabase) -> list[LandmarkResponse]:
    docs = await db.landmarks.find({"status": LandmarkStatus.pending}).to_list(None)
    return [_doc_to_landmark(doc) for doc in docs]


async def approve_landmark(db: AsyncIOMotorDatabase, landmark_id: str) -> LandmarkResponse | None:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    await db.landmarks.update_one({"_id": oid}, {"$set": {"status": LandmarkStatus.approved, "has_active_quest": True}})
    return await get_landmark_by_id(db, landmark_id)


async def reject_landmark(db: AsyncIOMotorDatabase, landmark_id: str) -> bool:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return False
    result = await db.landmarks.update_one({"_id": oid}, {"$set": {"status": LandmarkStatus.rejected}})
    return result.modified_count > 0


async def get_all_submissions(db: AsyncIOMotorDatabase) -> list[LandmarkResponse]:
    """All user-submitted landmarks (any status)."""
    docs = await db.landmarks.find({"submitted_by": {"$exists": True}}).to_list(None)
    return [_doc_to_landmark(doc) for doc in docs]


async def get_own_submissions(db: AsyncIOMotorDatabase, user_id: str) -> list[LandmarkResponse]:
    """Landmarks submitted by the current user (any status)."""
    docs = await db.landmarks.find({"submitted_by": user_id}).to_list(None)
    return [_doc_to_landmark(doc) for doc in docs]


async def edit_landmark(db: AsyncIOMotorDatabase, landmark_id: str, payload: LandmarkEdit) -> LandmarkResponse | None:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    updates = {k: v for k, v in {
        "name": payload.name,
        "type": payload.type.value if payload.type else None,
        "description": payload.description,
        "categories": payload.categories,
        "website": payload.website,
        "opening_hours": payload.opening_hours,
    }.items() if v is not None}
    if not updates:
        return await get_landmark_by_id(db, landmark_id)
    await db.landmarks.update_one({"_id": oid}, {"$set": updates})
    return await get_landmark_by_id(db, landmark_id)


async def submit_story(db: AsyncIOMotorDatabase, landmark_id: str, user_id: str, text: str) -> StoryResponse | None:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    lm = await db.landmarks.find_one({"_id": oid})
    if not lm:
        return None
    if len(lm.get("stories", [])) >= _MAX_STORIES:
        raise HTTPException(status_code=422, detail=f"Landmark already has {_MAX_STORIES} stories (maximum)")
    # Admins and the landmark's own creator bypass the review queue
    user_doc = await db.users.find_one({"_id": ObjectId(user_id)})
    is_admin = user_doc.get("is_admin", False) if user_doc else False
    is_creator = lm.get("submitted_by") == user_id
    # Award 5 points for submitting a story regardless of outcome
    await db.users.update_one({"_id": ObjectId(user_id)}, {"$inc": {"points": 5}})

    if is_admin or is_creator:
        await db.landmarks.update_one({"_id": oid}, {"$push": {"stories": text.strip()}})
        return StoryResponse(
            id="direct",
            landmark_id=landmark_id,
            landmark_name=lm.get("name"),
            text=text.strip(),
            status="approved",
            submitted_by=user_id,
        )
    result = await db.stories.insert_one({
        "landmark_id": landmark_id,
        "submitted_by": user_id,
        "text": text.strip(),
        "status": "pending",
    })
    return StoryResponse(
        id=str(result.inserted_id),
        landmark_id=landmark_id,
        landmark_name=lm.get("name"),
        text=text.strip(),
        status="pending",
    )


async def get_pending_stories_for_owner(db: AsyncIOMotorDatabase, user_id: str) -> list[StoryResponse]:
    owned = await db.landmarks.find({"submitted_by": user_id}, {"_id": 1, "name": 1}).to_list(None)
    owned_ids = [str(lm["_id"]) for lm in owned]
    if not owned_ids:
        return []
    docs = await db.stories.find({"status": "pending", "landmark_id": {"$in": owned_ids}}).to_list(None)
    name_map = {str(lm["_id"]): lm.get("name") for lm in owned}
    return [
        StoryResponse(
            id=str(doc["_id"]),
            landmark_id=doc["landmark_id"],
            landmark_name=name_map.get(doc["landmark_id"]),
            text=doc["text"],
            status=doc["status"],
            submitted_by=doc.get("submitted_by"),
        )
        for doc in docs
    ]


async def get_pending_stories(db: AsyncIOMotorDatabase) -> list[StoryResponse]:
    docs = await db.stories.find({"status": "pending"}).to_list(None)
    results = []
    for doc in docs:
        lm = await db.landmarks.find_one({"_id": ObjectId(doc["landmark_id"])}, {"name": 1})
        results.append(StoryResponse(
            id=str(doc["_id"]),
            landmark_id=doc["landmark_id"],
            landmark_name=lm.get("name") if lm else None,
            text=doc["text"],
            status=doc["status"],
            submitted_by=doc.get("submitted_by"),
        ))
    return results


async def approve_story(db: AsyncIOMotorDatabase, story_id: str) -> bool:
    try:
        oid = ObjectId(story_id)
    except InvalidId:
        return False
    doc = await db.stories.find_one({"_id": oid})
    if not doc:
        return False
    await db.stories.update_one({"_id": oid}, {"$set": {"status": "approved"}})
    # Append to landmark's stories array
    await db.landmarks.update_one(
        {"_id": ObjectId(doc["landmark_id"])},
        {"$push": {"stories": doc["text"]}},
    )
    return True


async def reject_story(db: AsyncIOMotorDatabase, story_id: str) -> bool:
    try:
        oid = ObjectId(story_id)
    except InvalidId:
        return False
    result = await db.stories.update_one({"_id": oid}, {"$set": {"status": "rejected"}})
    return result.modified_count > 0


async def delete_landmark(db: AsyncIOMotorDatabase, landmark_id: str) -> bool:
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return False
    result = await db.landmarks.delete_one({"_id": oid})
    return result.deleted_count > 0
