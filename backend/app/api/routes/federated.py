from fastapi import APIRouter, Depends
from app.api.deps import get_current_user, get_admin_user, get_redis
from app.models.user import ModelUpdate, InitializePayload
from app.services.fl_service import get_global_weights, submit_client_update, get_fl_status, initialize_model

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
    result = await submit_client_update(redis, payload.weights, payload.num_samples, client_round=payload.round, user_id=user_id, algorithm=payload.algorithm)
    return result


@router.post("/admin/initialize")
async def initialize_global_model(
    payload: InitializePayload,
    _=Depends(get_admin_user),
    redis=Depends(get_redis),
):
    """Load pre-trained weights as the new global model. Resets round and FL history."""
    await initialize_model(redis, payload.weights)
    return {"status": "initialized", "layers": len(payload.weights), "round": 0}


@router.get("/model/status")
async def fl_status(redis=Depends(get_redis)):
    """Return current FL round number and status."""
    return await get_fl_status(redis)
