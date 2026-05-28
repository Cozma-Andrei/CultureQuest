from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from fastapi import HTTPException

from app.models.quest import QuestResponse


def _doc_to_quest(doc: dict, completed_ids: set[str] | None = None) -> QuestResponse:
    quest_id = str(doc["_id"])
    return QuestResponse(
        id=quest_id,
        landmark_id=str(doc["landmark_id"]),
        type=doc["type"],
        title=doc["title"],
        description=doc["description"],
        points=doc["points"],
        options=doc.get("options", []),
        correct_option_index=doc.get("correct_option_index"),
        completed=quest_id in (completed_ids or set()),
    )


async def get_quests_for_landmark(
    db: AsyncIOMotorDatabase, landmark_id: str, user_id: str
) -> list[QuestResponse]:
    user = await db.users.find_one({"_id": ObjectId(user_id)})
    completed_ids = set(user.get("completed_quest_ids", [])) if user else set()
    docs = await db.quests.find({"landmark_id": landmark_id}).to_list(50)
    return [_doc_to_quest(doc, completed_ids) for doc in docs]


async def complete_quest(
    db: AsyncIOMotorDatabase,
    quest_id: str,
    user_id: str,
    answer_index: int | None,
    note_text: str | None,
) -> dict:
    try:
        quest_oid = ObjectId(quest_id)
        user_oid = ObjectId(user_id)
    except InvalidId:
        raise HTTPException(status_code=400, detail="Invalid ID")

    quest = await db.quests.find_one({"_id": quest_oid})
    if not quest:
        raise HTTPException(status_code=404, detail="Quest not found")

    user = await db.users.find_one({"_id": user_oid})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if quest_id in user.get("completed_quest_ids", []):
        return {
            "correct": True,
            "points_earned": 0,
            "already_completed": True,
            "total_points": user.get("points", 0),
            "total_completed": user.get("completed_quests", 0),
        }

    correct = True
    if quest["type"] == "educational" and quest.get("correct_option_index") is not None:
        correct = answer_index == quest["correct_option_index"]

    points_earned = quest["points"] if correct else 0

    if correct:
        await db.users.update_one(
            {"_id": user_oid},
            {
                "$inc": {"points": points_earned, "completed_quests": 1},
                "$push": {"completed_quest_ids": quest_id},
            },
        )

    updated = await db.users.find_one({"_id": user_oid})
    return {
        "correct": correct,
        "points_earned": points_earned,
        "already_completed": False,
        "total_points": updated.get("points", 0),
        "total_completed": updated.get("completed_quests", 0),
    }


async def get_user_progress(db: AsyncIOMotorDatabase, user_id: str) -> dict:
    try:
        user = await db.users.find_one({"_id": ObjectId(user_id)})
    except InvalidId:
        user = None
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "points": user.get("points", 0),
        "completed_quests": user.get("completed_quests", 0),
        "completed_quest_ids": user.get("completed_quest_ids", []),
    }


_QUEST_TEMPLATES: dict[str, list[dict]] = {
    "Nearby Test Spot": [
        dict(type="educational", title="When Was It Built?",
             description="What year does this monument date back to?",
             points=30, options=["1870", "1900", "1920", "1945"], correct_option_index=1),
        dict(type="mission", title="Close Inspection",
             description="Walk around the monument and note any inscriptions you find.",
             points=20, options=[], correct_option_index=None),
    ],
    "City Art Museum": [
        dict(type="educational", title="Museum Origins",
             description="In what year was this museum founded?",
             points=30, options=["1820", "1892", "1910", "1950"], correct_option_index=1),
        dict(type="challenge", title="Find the Oldest",
             description="Find the oldest artwork in the museum and note its title and year.",
             points=50, options=[], correct_option_index=None),
        dict(type="virtual_note", title="Favorite Piece",
             description="Share your favorite artwork from this museum and why it moved you.",
             points=15, options=[], correct_option_index=None),
    ],
    "Central Monument": [
        dict(type="educational", title="What's Commemorated?",
             description="What event does this monument commemorate?",
             points=30,
             options=["A famous battle", "The city's founding", "Independence day", "A royal coronation"],
             correct_option_index=1),
        dict(type="mission", title="Step Counter",
             description="Count the number of steps or plaques around the base of the monument.",
             points=20, options=[], correct_option_index=None),
    ],
    "City Park": [
        dict(type="mission", title="Oldest Tree",
             description="Find and photograph what you believe is the oldest tree in the park.",
             points=25, options=[], correct_option_index=None),
        dict(type="challenge", title="Full Lap",
             description="Walk the entire perimeter of the park without stopping.",
             points=40, options=[], correct_option_index=None),
    ],
    "Old Town Square": [
        dict(type="educational", title="Architectural Style",
             description="What architectural style is predominant around this square?",
             points=30, options=["Gothic", "Baroque", "Renaissance", "Art Deco"],
             correct_option_index=1),
        dict(type="virtual_note", title="Square Atmosphere",
             description="Describe the current atmosphere of the square in a few sentences.",
             points=15, options=[], correct_option_index=None),
    ],
    "Contemporary Gallery": [
        dict(type="educational", title="Defining Contemporary Art",
             description="Contemporary art generally refers to art made:",
             points=20,
             options=["Before the 20th century", "Since the 1970s", "Only digitally", "In any historical era"],
             correct_option_index=1),
        dict(type="challenge", title="Most Unusual Piece",
             description="Find the most unusual artwork on display and be ready to explain your choice.",
             points=35, options=[], correct_option_index=None),
    ],
    "Traditional Restaurant": [
        dict(type="educational", title="Family Recipe",
             description="How many generations has the signature dish recipe been passed down?",
             points=20, options=["Two", "Three", "Five", "Eight"], correct_option_index=2),
        dict(type="virtual_note", title="Your Order",
             description="What did you order, and how did it taste?",
             points=15, options=[], correct_option_index=None),
    ],
    "Historic Cathedral": [
        dict(type="educational", title="Construction Start",
             description="When did construction of this cathedral begin?",
             points=30, options=["1323", "1423", "1523", "1623"], correct_option_index=1),
        dict(type="educational", title="Build Duration",
             description="How many years did the construction take to complete?",
             points=25, options=["40 years", "60 years", "80 years", "100 years"],
             correct_option_index=2),
    ],
    "Music Conservatory": [
        dict(type="educational", title="Founding Year",
             description="When was this conservatory founded?",
             points=25, options=["1820", "1870", "1900", "1920"], correct_option_index=1),
        dict(type="mission", title="Attend a Concert",
             description="Check the schedule and attend one of the public concerts held here.",
             points=50, options=[], correct_option_index=None),
    ],
}


async def seed_quests_for_landmark(
    db: AsyncIOMotorDatabase, landmark_id: str, landmark_name: str
) -> int:
    templates = _QUEST_TEMPLATES.get(landmark_name, [
        dict(type="mission", title="Explore",
             description="Take a moment to explore this location and its surroundings.",
             points=15, options=[], correct_option_index=None),
    ])
    docs = [
        {
            "landmark_id": landmark_id,
            "type": t["type"],
            "title": t["title"],
            "description": t["description"],
            "points": t["points"],
            "options": t["options"],
            "correct_option_index": t["correct_option_index"],
            "seeded": True,
        }
        for t in templates
    ]
    if docs:
        await db.quests.insert_many(docs)
    return len(docs)
