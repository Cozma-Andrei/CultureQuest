from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.quest import QuestResponse, QuestCompletionPayload
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
