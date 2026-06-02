from datetime import datetime
from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from fastapi import HTTPException, status

from app.core.security import hash_password, verify_password, create_access_token
from app.models.user import UserCreate, UserLogin, UserProfile, TokenResponse, InterestCategory


def _doc_to_profile(doc: dict) -> UserProfile:
    return UserProfile(
        id=str(doc["_id"]),
        email=doc["email"],
        name=doc["name"],
        interests=doc.get("interests", []),
        points=doc.get("points", 0),
        completed_quests=doc.get("completed_quests", 0),
        is_admin=doc.get("is_admin", False),
    )


async def register_user(db: AsyncIOMotorDatabase, payload: UserCreate) -> TokenResponse:
    if await db.users.find_one({"email": payload.email}):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

    doc = {
        "email": payload.email,
        "password_hash": hash_password(payload.password),
        "name": payload.name,
        "interests": [i.value for i in payload.interests],
        "points": 0,
        "completed_quests": 0,
        "created_at": datetime.utcnow(),
    }
    result = await db.users.insert_one(doc)
    doc["_id"] = result.inserted_id

    return TokenResponse(
        access_token=create_access_token(str(result.inserted_id)),
        user=_doc_to_profile(doc),
    )


async def login_user(db: AsyncIOMotorDatabase, payload: UserLogin) -> TokenResponse:
    doc = await db.users.find_one({"email": payload.email})
    if not doc or not verify_password(payload.password, doc["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    return TokenResponse(
        access_token=create_access_token(str(doc["_id"])),
        user=_doc_to_profile(doc),
    )


async def get_user_by_id(db: AsyncIOMotorDatabase, user_id: str) -> UserProfile:
    try:
        doc = await db.users.find_one({"_id": ObjectId(user_id)})
    except InvalidId:
        doc = None
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return _doc_to_profile(doc)


async def update_interests(db: AsyncIOMotorDatabase, user_id: str, interests: list[InterestCategory]) -> UserProfile:
    try:
        await db.users.update_one(
            {"_id": ObjectId(user_id)},
            {"$set": {"interests": [i.value for i in interests]}},
        )
    except InvalidId:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return await get_user_by_id(db, user_id)
