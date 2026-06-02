from bson import ObjectId
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query
from app.api.deps import get_current_user, get_db
from app.models.user import LocationUpdate, NearbyUser
from app.core.security import decode_token

router = APIRouter()

# Default radius for user-to-user proximity notifications (metres)
_DEFAULT_RADIUS_M = 100


@router.post("/me/reset-progress", status_code=204)
async def reset_progress(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    """Reset points and completed_quests to 0. Interests are preserved."""
    await db.users.update_one(
        {"_id": ObjectId(user_id)},
        {"$set": {"points": 0, "completed_quests": 0}},
    )


@router.post("/location")
async def update_location(payload: LocationUpdate, user=Depends(get_current_user), db=Depends(get_db)):
    """Store the user's current location (opt-in). Used for nearby-user queries."""
    pass


@router.get("/nearby", response_model=list[NearbyUser])
async def nearby_users(
    lat: float,
    lng: float,
    radius_m: int = _DEFAULT_RADIUS_M,
    user=Depends(get_current_user),
    db=Depends(get_db),
):
    """Return opted-in users within radius_m metres (MongoDB 2dsphere query)."""
    pass


@router.websocket("/ws/proximity")
async def proximity_ws(websocket: WebSocket, token: str = Query(...), db=Depends(get_db)):
    """
    Persistent WebSocket for real-time user-to-user proximity.

    Protocol:
      Client → server:  {"lat": float, "lng": float}
      Server → client:  {"type": "nearby_user", "user_id": str, "display_name": str, "distance_m": float}
    """
    user_id = decode_token(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            # TODO: update user location in DB, query nearby users, push events
    except WebSocketDisconnect:
        pass
