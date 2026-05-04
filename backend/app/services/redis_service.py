from redis.asyncio import Redis


async def cache_set(redis: Redis, key: str, value: str, ttl: int = 300) -> None:
    pass


async def cache_get(redis: Redis, key: str) -> str | None:
    pass


async def cache_delete(redis: Redis, key: str) -> None:
    pass


async def store_fl_round_state(redis: Redis, round_num: int, data: dict) -> None:
    pass


async def get_fl_round_state(redis: Redis, round_num: int) -> dict | None:
    pass
