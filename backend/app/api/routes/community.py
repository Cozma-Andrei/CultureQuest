from fastapi import APIRouter, Depends, HTTPException, status
from bson import ObjectId
from bson.errors import InvalidId
from app.api.deps import get_current_user, get_db

router = APIRouter()

_VOTES_NEEDED = 5


async def _vote(db, collection: str, item_id: str, user_id: str, auto_approve_fn) -> dict:
    try:
        oid = ObjectId(item_id)
    except InvalidId:
        raise HTTPException(status_code=404, detail="Item not found")

    doc = await db[collection].find_one({"_id": oid, "status": "pending"})
    if not doc:
        raise HTTPException(status_code=404, detail="Pending item not found")

    if doc.get("submitted_by") == user_id:
        raise HTTPException(status_code=403, detail="You cannot validate your own submission")

    # Increment anonymous vote counter: no user ID stored
    new_count = doc.get("community_vote_count", 0) + 1
    approved = new_count >= _VOTES_NEEDED

    update: dict = {"$set": {"community_vote_count": new_count}}
    if approved:
        update["$set"]["status"] = "approved"

    await db[collection].update_one({"_id": oid}, update)

    if approved:
        await auto_approve_fn(db, doc)

    return {"votes": new_count, "needed": _VOTES_NEEDED, "approved": approved}


async def _approve_landmark(db, doc):
    await db.landmarks.update_one(
        {"_id": ObjectId(str(doc["_id"]))},
        {"$set": {"status": "approved", "has_active_quest": True}},
    )


async def _approve_story(db, doc):
    await db.landmarks.update_one(
        {"_id": ObjectId(doc["landmark_id"])},
        {"$push": {"stories": doc["text"]}},
    )


async def _approve_quest(db, doc):
    await db.landmarks.update_one(
        {"_id": ObjectId(doc["landmark_id"])},
        {"$set": {"has_active_quest": True}},
    )


@router.post("/vote/story/{item_id}")
async def vote_story(item_id: str, user_id=Depends(get_current_user), db=Depends(get_db)):
    return await _vote(db, "stories", item_id, user_id, _approve_story)


@router.post("/vote/quest/{item_id}")
async def vote_quest(item_id: str, user_id=Depends(get_current_user), db=Depends(get_db)):
    return await _vote(db, "quests", item_id, user_id, _approve_quest)


@router.get("/pending")
async def all_pending(user_id=Depends(get_current_user), db=Depends(get_db)):
    """Returns pending stories and quests for community review.
    Locations are handled by admin only."""
    result = {"stories": [], "quests": []}

    async for doc in db.stories.find({"status": "pending"}):
        lm = await db.landmarks.find_one({"_id": ObjectId(doc["landmark_id"])}, {"name": 1})
        result["stories"].append({
            "id": str(doc["_id"]),
            "landmark_id": doc["landmark_id"],
            "landmark_name": lm.get("name") if lm else "",
            "text": doc.get("text", ""),
            "votes": doc.get("community_vote_count", 0),
            "needed": _VOTES_NEEDED,
            "is_own": doc.get("submitted_by") == user_id,
        })

    async for doc in db.quests.find({"status": "pending"}):
        lm = await db.landmarks.find_one({"_id": ObjectId(doc["landmark_id"])}, {"name": 1})
        result["quests"].append({
            "id": str(doc["_id"]),
            "landmark_id": doc["landmark_id"],
            "landmark_name": lm.get("name") if lm else "",
            "title": doc.get("title", ""),
            "type": doc.get("type", ""),
            "description": doc.get("description", ""),
            "votes": doc.get("community_vote_count", 0),
            "needed": _VOTES_NEEDED,
            "is_own": doc.get("submitted_by") == user_id,
        })

    return result
