from bson import ObjectId
from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_admin_user, get_db
from app.models.quest import QuestResponse, QuestCompletionPayload, QuestSubmit, QuestSubmitResponse
from app.services import quest_service

router = APIRouter()


@router.get("/", response_model=list[QuestResponse])
async def list_quests(landmark_id: str, user=Depends(get_current_user), db=Depends(get_db)):
    return await quest_service.get_quests_for_landmark(db, landmark_id, user)


@router.get("/me/progress")
async def my_progress(user=Depends(get_current_user), db=Depends(get_db)):
    return await quest_service.get_user_progress(db, user)


@router.post("/{quest_id}/complete")
async def complete_quest(
    quest_id: str,
    payload: QuestCompletionPayload,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    return await quest_service.complete_quest(
        db, quest_id, user, payload.answer_index, payload.note_text
    )


@router.post("/submit/{landmark_id}", status_code=201)
async def submit_quest(
    landmark_id: str,
    payload: QuestSubmit,
    user_id: str = Depends(get_current_user),
    db=Depends(get_db),
):
    result = await quest_service.submit_quest(db, landmark_id, user_id, payload)
    if not result:
        raise HTTPException(status_code=404, detail="Landmark not found")
    return result


@router.get("/owner/pending")
async def pending_quests_owner(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await quest_service.get_pending_quests_for_owner(db, user_id)


@router.get("/admin/pending")
async def pending_quests(_=Depends(get_admin_user), db=Depends(get_db)):
    return await quest_service.get_pending_quests(db)


async def _check_admin_or_quest_owner(db, quest_id: str, user_id: str):
    user_doc = await db.users.find_one({"_id": ObjectId(user_id)})
    if user_doc and user_doc.get("is_admin", False):
        return
    quest = await db.quests.find_one({"_id": ObjectId(quest_id)})
    if not quest:
        raise HTTPException(status_code=404, detail="Quest not found")
    lm = await db.landmarks.find_one({"_id": ObjectId(quest["landmark_id"])})
    if not lm or lm.get("submitted_by") != user_id:
        raise HTTPException(status_code=403, detail="Admin or landmark creator access required")


@router.post("/admin/{quest_id}/approve", status_code=204)
async def approve_quest(quest_id: str, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    await _check_admin_or_quest_owner(db, quest_id, user_id)
    ok = await quest_service.approve_quest(db, quest_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Quest not found")


@router.post("/admin/{quest_id}/reject", status_code=204)
async def reject_quest(quest_id: str, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    await _check_admin_or_quest_owner(db, quest_id, user_id)
    ok = await quest_service.reject_quest(db, quest_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Quest not found")
