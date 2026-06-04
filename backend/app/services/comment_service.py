import os
import re
from datetime import datetime
from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from app.models.landmark import CommentCreate, CommentResponse

_MAX_COMMENTS = 50  # per landmark

# Local fallback — catches slurs and severe harassment when OpenAI is unavailable
_BLOCKED = re.compile(
    r'\b(nigga|nigger|faggot|fag|kike|spic|chink|cunt|whore|bitch|retard|'
    r'motherfuck|kill\s+your?self|go\s+die|piece\s+of\s+shit|fuck\s+you)\b',
    re.IGNORECASE,
)

def _local_flag(text: str) -> bool:
    return bool(_BLOCKED.search(text))


def _doc_to_comment(doc: dict) -> CommentResponse:
    return CommentResponse(
        id=str(doc["_id"]),
        landmark_id=doc["landmark_id"],
        text=doc["text"],
        rating=doc["rating"],
        created_at=doc.get("created_at", ""),
        flagged=doc.get("flagged", False),
        flag_source=doc.get("flag_source"),
    )


async def _moderate(text: str, comment_id: str, db: AsyncIOMotorDatabase) -> bool:
    """Returns True if the text is flagged. Tries OpenAI first, local keywords as fallback."""
    flagged = False
    categories: list[str] = []
    source: str = "local"

    api_key = os.getenv("OPENAI_API_KEY")
    if api_key:
        try:
            import httpx
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    "https://api.openai.com/v1/moderations",
                    headers={"Authorization": f"Bearer {api_key}"},
                    json={"input": text},
                )
                if resp.status_code == 200:
                    data = resp.json()
                    result = data["results"][0]
                    flagged = result.get("flagged", False)
                    if flagged:
                        categories = [k for k, v in result.get("categories", {}).items() if v]
                        source = "openai"
        except Exception:
            pass

    # Local keyword fallback — runs when OpenAI is unavailable or returned non-200
    if not flagged and _local_flag(text):
        flagged = True
        categories = ["harassment"]
        source = "local"

    if flagged:
        await db.comments.update_one(
            {"_id": ObjectId(comment_id)},
            {"$set": {"flagged": True, "flag_categories": categories, "flag_source": source}},
        )

    return flagged


async def submit_comment(
    db: AsyncIOMotorDatabase, landmark_id: str, payload: CommentCreate
) -> CommentResponse | None:
    try:
        ObjectId(landmark_id)
    except InvalidId:
        return None
    lm = await db.landmarks.find_one({"_id": ObjectId(landmark_id)}, {"_id": 1})
    if not lm:
        return None
    if not (1 <= payload.rating <= 5):
        return None

    doc = {
        "landmark_id": landmark_id,
        "text": payload.text.strip(),
        "rating": payload.rating,
        "created_at": datetime.utcnow().isoformat(),
        "flagged": False,
    }
    result = await db.comments.insert_one(doc)
    comment_id = str(result.inserted_id)
    doc["_id"] = result.inserted_id

    # Synchronous moderation — caller gets accurate flagged status
    flagged = await _moderate(payload.text.strip(), comment_id, db)
    doc["flagged"] = flagged

    return _doc_to_comment(doc)


async def update_comment(
    db: AsyncIOMotorDatabase, comment_id: str, payload: CommentCreate
) -> CommentResponse | None:
    """Replace an existing comment's text/rating (used for re-review)."""
    try:
        oid = ObjectId(comment_id)
    except InvalidId:
        return None

    update_data = {
        "text": payload.text.strip(),
        "rating": payload.rating,
        "created_at": datetime.utcnow().isoformat(),
        "flagged": False,
    }
    doc = await db.comments.find_one_and_update(
        {"_id": oid},
        {"$set": update_data},
        return_document=True,
    )
    if not doc:
        return None

    flagged = await _moderate(payload.text.strip(), comment_id, db)
    doc["flagged"] = flagged

    return _doc_to_comment(doc)


async def get_comments(db: AsyncIOMotorDatabase, landmark_id: str) -> list[CommentResponse]:
    docs = await db.comments.find(
        {"landmark_id": landmark_id, "flagged": False, "text": {"$ne": ""}}
    ).sort("created_at", -1).limit(_MAX_COMMENTS).to_list(None)
    return [_doc_to_comment(doc) for doc in docs]


async def get_flagged_comments(db: AsyncIOMotorDatabase) -> list[CommentResponse]:
    docs = await db.comments.find({"flagged": True}).sort("created_at", -1).to_list(None)
    return [_doc_to_comment(doc) for doc in docs]


async def delete_comment(db: AsyncIOMotorDatabase, comment_id: str) -> bool:
    try:
        oid = ObjectId(comment_id)
    except InvalidId:
        return False
    result = await db.comments.delete_one({"_id": oid})
    return result.deleted_count > 0
