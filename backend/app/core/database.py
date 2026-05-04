from motor.motor_asyncio import AsyncIOMotorClient
from redis.asyncio import Redis
from app.core.config import settings

mongo_client: AsyncIOMotorClient = None
redis_client: Redis = None


def get_database():
    return mongo_client[settings.mongo_db]


async def connect_db():
    global mongo_client, redis_client
    mongo_client = AsyncIOMotorClient(settings.mongo_uri)
    redis_client = Redis.from_url(settings.redis_url, decode_responses=True)


async def close_db():
    if mongo_client:
        mongo_client.close()
    if redis_client:
        await redis_client.close()
