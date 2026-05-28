from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_redis
from app.models.user import ModelUpdate
from app.services.fl_service import get_global_weights, submit_client_update, get_fl_status

router = APIRouter()


@router.get("/model/global")
async def get_global_model(redis=Depends(get_redis)):
    """Return the current global model weights for the FL client to download."""
    round_num, weights = await get_global_weights(redis)
    return {"round": round_num, "weights": weights}


@router.post("/model/update")
async def receive_model_update(
    payload: ModelUpdate,
    user_id: str = Depends(get_current_user),
    redis=Depends(get_redis),
):
    """Accept local weight updates from a device and run FedAvg aggregation."""
    result = await submit_client_update(redis, payload.weights, payload.num_samples, user_id=user_id)
    return result


@router.get("/model/status")
async def fl_status(redis=Depends(get_redis)):
    """Return current FL round number and status."""
    return await get_fl_status(redis)
