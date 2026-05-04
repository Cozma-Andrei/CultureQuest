from motor.motor_asyncio import AsyncIOMotorDatabase
from app.models.route import RouteRequest, RouteResponse


async def generate_cultural_route(db: AsyncIOMotorDatabase, user_id: str, request: RouteRequest) -> RouteResponse:
    """Generate a personalised cultural route using MLP relevance scores."""
    pass


async def get_route(db: AsyncIOMotorDatabase, route_id: str) -> RouteResponse | None:
    pass


async def get_user_routes(db: AsyncIOMotorDatabase, user_id: str) -> list[RouteResponse]:
    pass
