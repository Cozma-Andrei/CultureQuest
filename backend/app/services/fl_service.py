import asyncio
import json
import os
import uuid
from contextlib import asynccontextmanager
from redis.asyncio import Redis
from app.federated.model import build_initial_weights, fedavg, clipped_fedavg

FL_WEIGHTS_KEY   = "fl:global_weights"
FL_ROUND_KEY     = "fl:round"
FL_CLIENTS_KEY   = "fl:client_ids"     # Redis set of unique contributor user_ids
FL_SAMPLES_KEY   = "fl:total_samples"  # running total of training samples aggregated
FL_ALGORITHM_KEY = "fl:algorithm"      # last client-reported training algorithm
FL_LAST_STALENESS_KEY = "fl:last_staleness"  # staleness of the most recent client upload
FL_LOCK_KEY      = "fl:agg_lock"            # mutual exclusion for the read-aggregate-write cycle

_LOCK_TTL_MS  = 5_000   # lock auto-expires after 5 s (guards against crashes)
_LOCK_RETRIES = 10
_LOCK_RETRY_DELAY = 0.3  # seconds between retries


@asynccontextmanager
async def _fl_lock(redis: Redis):
    """Async context manager that holds a Redis lock for the aggregation cycle.

    Uses SET NX PX — one Redis instance, no redlock needed.
    Raises RuntimeError if the lock cannot be acquired after all retries.
    """
    token = str(uuid.uuid4())
    acquired = False
    for _ in range(_LOCK_RETRIES):
        ok = await redis.set(FL_LOCK_KEY, token, nx=True, px=_LOCK_TTL_MS)
        if ok:
            acquired = True
            break
        await asyncio.sleep(_LOCK_RETRY_DELAY)
    if not acquired:
        raise RuntimeError("FL aggregation lock timeout — server busy, retry later")
    try:
        yield
    finally:
        # Only delete if we still own it (Lua script for atomicity)
        _RELEASE_SCRIPT = """
        if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
        else
            return 0
        end
        """
        await redis.eval(_RELEASE_SCRIPT, 1, FL_LOCK_KEY, token)


async def get_global_weights(redis: Redis) -> tuple[int, list[list[float]]]:
    round_num = int(await redis.get(FL_ROUND_KEY) or 0)
    raw = await redis.get(FL_WEIGHTS_KEY)
    if raw is None:
        weights = build_initial_weights()
        await redis.set(FL_WEIGHTS_KEY, json.dumps(weights))
        await redis.set(FL_ROUND_KEY, 0)
        return 0, weights
    return round_num, json.loads(raw)


async def submit_client_update(
    redis: Redis,
    client_weights: list[list[float]],
    num_samples: int,
    client_round: int = 0,
    user_id: str = "",
    algorithm: str = "fedprox",
) -> dict:
    async with _fl_lock(redis):
        current_round, global_weights = await get_global_weights(redis)
        staleness = max(0, current_round - client_round)
        discount = 1.0 / (1.0 + staleness)
        effective_samples = max(1, round(num_samples * discount))
        global_virtual_samples = max(effective_samples * 4, 20)
        new_weights = clipped_fedavg(
            [(effective_samples, client_weights), (global_virtual_samples, global_weights)],
            global_weights,
            max_norm=1.0,
        )
        new_round = current_round + 1
        await redis.set(FL_WEIGHTS_KEY, json.dumps(new_weights))
        await redis.set(FL_ROUND_KEY, str(new_round))
        await redis.set(FL_ALGORITHM_KEY, algorithm)
        await redis.set(FL_LAST_STALENESS_KEY, str(staleness))
        if user_id:
            await redis.sadd(FL_CLIENTS_KEY, user_id)
        await redis.incrby(FL_SAMPLES_KEY, num_samples)
    return {
        "round": new_round,
        "aggregated": True,
        "num_samples": num_samples,
        "staleness": staleness,
        "effective_samples": effective_samples,
    }


async def initialize_model(redis: Redis, weights: list[list[float]]) -> None:
    """Replace global model with pre-trained weights. Resets all FL history."""
    await redis.set(FL_WEIGHTS_KEY, json.dumps(weights))
    await redis.set(FL_ROUND_KEY, '0')
    await redis.delete(FL_CLIENTS_KEY)
    await redis.set(FL_SAMPLES_KEY, '0')


async def get_fl_status(redis: Redis) -> dict:
    round_num      = int(await redis.get(FL_ROUND_KEY)        or 0)
    num_clients    = int(await redis.scard(FL_CLIENTS_KEY)    or 0)
    total_samples  = int(await redis.get(FL_SAMPLES_KEY)      or 0)
    algorithm      = await redis.get(FL_ALGORITHM_KEY)
    last_staleness_raw = await redis.get(FL_LAST_STALENESS_KEY)
    last_staleness = int(last_staleness_raw) if last_staleness_raw is not None else None
    return {
        "round": round_num,
        "status": "active",
        "num_clients": num_clients,
        "total_samples": total_samples,
        "algorithm": algorithm,
        "last_staleness": last_staleness,
    }
