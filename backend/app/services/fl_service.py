import json
from redis.asyncio import Redis
from app.federated.model import build_initial_weights, fedavg, clipped_fedavg

FL_WEIGHTS_KEY   = "fl:global_weights"
FL_ROUND_KEY     = "fl:round"
FL_CLIENTS_KEY   = "fl:client_ids"     # Redis set of unique contributor user_ids
FL_SAMPLES_KEY   = "fl:total_samples"  # running total of training samples aggregated
FL_ALGORITHM_KEY = "fl:algorithm"      # last client-reported training algorithm


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
    user_id: str = "",
    algorithm: str = "fedprox",
) -> dict:
    current_round, global_weights = await get_global_weights(redis)
    global_virtual_samples = max(num_samples * 4, 20)
    new_weights = clipped_fedavg(
        [(num_samples, client_weights), (global_virtual_samples, global_weights)],
        global_weights,
        max_norm=1.0,
    )
    new_round = current_round + 1
    await redis.set(FL_WEIGHTS_KEY, json.dumps(new_weights))
    await redis.set(FL_ROUND_KEY, str(new_round))
    await redis.set(FL_ALGORITHM_KEY, algorithm)
    if user_id:
        await redis.sadd(FL_CLIENTS_KEY, user_id)
    await redis.incrby(FL_SAMPLES_KEY, num_samples)
    return {"round": new_round, "aggregated": True, "num_samples": num_samples}


async def initialize_model(redis: Redis, weights: list[list[float]]) -> None:
    """Replace global model with pre-trained weights. Resets all FL history."""
    await redis.set(FL_WEIGHTS_KEY, json.dumps(weights))
    await redis.set(FL_ROUND_KEY, '0')
    await redis.delete(FL_CLIENTS_KEY)
    await redis.set(FL_SAMPLES_KEY, '0')


async def get_fl_status(redis: Redis) -> dict:
    round_num     = int(await redis.get(FL_ROUND_KEY)    or 0)
    num_clients   = int(await redis.scard(FL_CLIENTS_KEY) or 0)
    total_samples = int(await redis.get(FL_SAMPLES_KEY)  or 0)
    algorithm     = await redis.get(FL_ALGORITHM_KEY)
    return {
        "round": round_num,
        "status": "active",
        "num_clients": num_clients,
        "total_samples": total_samples,
        "algorithm": algorithm,
    }
