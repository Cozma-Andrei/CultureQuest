from motor.motor_asyncio import AsyncIOMotorDatabase
from app.models.landmark import LandmarkCreate, LandmarkResponse


async def get_nearby_landmarks(db: AsyncIOMotorDatabase, lat: float, lng: float, radius_m: int) -> list[LandmarkResponse]:
    pass


async def get_landmark_by_id(db: AsyncIOMotorDatabase, landmark_id: str) -> LandmarkResponse | None:
    pass


async def create_landmark(db: AsyncIOMotorDatabase, payload: LandmarkCreate) -> LandmarkResponse:
    pass
