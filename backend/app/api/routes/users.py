from bson import ObjectId
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, Query
from app.api.deps import get_current_user, get_db
from app.models.user import LocationUpdate, NearbyUser, LeaderboardEntry, LeaderboardResponse
from app.core.security import decode_token

router = APIRouter()

# Default radius for user-to-user proximity notifications (metres)
_DEFAULT_RADIUS_M = 100


@router.get("/leaderboard", response_model=LeaderboardResponse)
async def leaderboard(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    """Return top 20 users by points, with the calling user's rank."""
    top = await db.users.find(
        {}, {"name": 1, "points": 1, "completed_quests": 1}
    ).sort([("points", -1), ("completed_quests", -1)]).to_list(20)

    entries = [
        LeaderboardEntry(
            rank=i + 1,
            name=u["name"],
            points=u.get("points", 0),
            completed_quests=u.get("completed_quests", 0),
            is_me=str(u["_id"]) == user_id,
        )
        for i, u in enumerate(top)
    ]

    my_rank = next((e.rank for e in entries if e.is_me), None)
    if my_rank is None:
        me = await db.users.find_one({"_id": ObjectId(user_id)}, {"points": 1, "completed_quests": 1})
        my_pts = me.get("points", 0) if me else 0
        my_qs  = me.get("completed_quests", 0) if me else 0
        count_ahead = await db.users.count_documents({
            "$or": [
                {"points": {"$gt": my_pts}},
                {"points": my_pts, "completed_quests": {"$gt": my_qs}},
            ]
        })
        my_rank = count_ahead + 1

    return LeaderboardResponse(my_rank=my_rank, leaderboard=entries)


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
