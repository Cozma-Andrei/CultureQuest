from fastapi import APIRouter, Depends
from app.api.deps import get_current_user
from app.models.user import ModelUpdate

router = APIRouter()


@router.get("/model/global")
async def get_global_model():
    """Return current global model weights for the FL client."""
    pass


@router.post("/model/update")
async def receive_model_update(payload: ModelUpdate, user=Depends(get_current_user)):
    """Receive local model update (weights/gradients) from a device."""
    pass


@router.get("/model/status")
async def fl_status():
    """Return current FL round info and number of participating clients."""
    pass
