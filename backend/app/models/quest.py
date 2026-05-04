from pydantic import BaseModel
from enum import Enum


class QuestType(str, Enum):
    educational = "educational"
    challenge = "challenge"
    mission = "mission"
    virtual_note = "virtual_note"


class QuestResponse(BaseModel):
    id: str
    landmark_id: str
    type: QuestType
    title: str
    description: str
    points: int
    options: list[str] = []
    correct_option_index: Optional[int] = None


class QuestCompletionPayload(BaseModel):
    answer_index: Optional[int] = None
    note_text: Optional[str] = None


from typing import Optional
