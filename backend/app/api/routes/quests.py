from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_db
from app.models.quest import QuestResponse, QuestCompletionPayload

router = APIRouter()


@router.get("/", response_model=list[QuestResponse])
async def list_quests(landmark_id: str, user=Depends(get_current_user), db=Depends(get_db)):
    pass


@router.post("/{quest_id}/complete")
async def complete_quest(quest_id: str, payload: QuestCompletionPayload, user=Depends(get_current_user), db=Depends(get_db)):
    pass


@router.get("/me/progress")
async def my_progress(user=Depends(get_current_user), db=Depends(get_db)):
    pass
