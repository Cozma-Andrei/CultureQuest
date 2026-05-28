from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from app.models.landmark import LandmarkCreate, LandmarkResponse, GeoPoint, LandmarkType
from app.services.quest_service import seed_quests_for_landmark


def _doc_to_landmark(doc: dict, visited_by_me: bool = False) -> LandmarkResponse:
    coords = doc["location"]["coordinates"]  # GeoJSON stores [lng, lat]
    return LandmarkResponse(
        id=str(doc["_id"]),
        name=doc["name"],
        type=doc["type"],
        location=GeoPoint(lat=coords[1], lng=coords[0]),
        description=doc["description"],
        categories=doc.get("categories", []),
        stories=doc.get("stories", []),
        rating=doc.get("rating", 0.0),
        visit_count=doc.get("visit_count", 0),
        has_active_quest=doc.get("has_active_quest", False),
        visited_by_me=visited_by_me,
    )


async def get_nearby_landmarks(
    db: AsyncIOMotorDatabase, lat: float, lng: float, radius_m: int, user_id: str | None = None
) -> list[LandmarkResponse]:
    cursor = db.landmarks.find({
        "location": {
            "$nearSphere": {
                "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                "$maxDistance": radius_m,
            }
        }
    }).limit(50)
    docs = await cursor.to_list(50)

    visited_ids: set[str] = set()
    if user_id and docs:
        landmark_ids = [str(d["_id"]) for d in docs]
        async for v in db.visits.find({"user_id": user_id, "landmark_id": {"$in": landmark_ids}}):
            visited_ids.add(v["landmark_id"])

    return [_doc_to_landmark(doc, visited_by_me=str(doc["_id"]) in visited_ids) for doc in docs]


async def get_all_landmarks(
    db: AsyncIOMotorDatabase, user_id: str | None = None
) -> list[LandmarkResponse]:
    docs = await db.landmarks.find({}).to_list(None)
    visited_ids: set[str] = set()
    if user_id and docs:
        landmark_ids = [str(d["_id"]) for d in docs]
        async for v in db.visits.find({"user_id": user_id, "landmark_id": {"$in": landmark_ids}}):
            visited_ids.add(v["landmark_id"])
    return [_doc_to_landmark(doc, visited_by_me=str(doc["_id"]) in visited_ids) for doc in docs]


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


async def record_visit(db: AsyncIOMotorDatabase, landmark_id: str, user_id: str) -> None:
    """Increment visit_count once per user per landmark."""
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return
    existing = await db.visits.find_one({"landmark_id": landmark_id, "user_id": user_id})
    if existing:
        return
    await db.visits.insert_one({"landmark_id": landmark_id, "user_id": user_id})
    await db.landmarks.update_one({"_id": oid}, {"$inc": {"visit_count": 1}})


async def rate_landmark(db: AsyncIOMotorDatabase, landmark_id: str, user_id: str, rating: int) -> LandmarkResponse | None:
    """Upsert a per-user rating and recompute the landmark average."""
    try:
        oid = ObjectId(landmark_id)
    except InvalidId:
        return None
    await db.ratings.update_one(
        {"landmark_id": landmark_id, "user_id": user_id},
        {"$set": {"rating": rating}},
        upsert=True,
    )
    pipeline = [
        {"$match": {"landmark_id": landmark_id}},
        {"$group": {"_id": None, "avg": {"$avg": "$rating"}}},
    ]
    cursor = db.ratings.aggregate(pipeline)
    result = await cursor.to_list(1)
    avg = round(result[0]["avg"], 2) if result else float(rating)
    await db.landmarks.update_one({"_id": oid}, {"$set": {"rating": avg}})
    return await get_landmark_by_id(db, landmark_id)


async def seed_landmarks(db: AsyncIOMotorDatabase, center_lat: float, center_lng: float) -> list[LandmarkResponse]:
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
        }
        result = await db.landmarks.insert_one(doc)
        doc["_id"] = result.inserted_id
        landmark = _doc_to_landmark(doc)
        created.append(landmark)
        await seed_quests_for_landmark(db, landmark.id, landmark.name)
    return created
