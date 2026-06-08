from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_admin_user, get_db
from app.models.landmark import CommentCreate, CommentResponse
from app.services.comment_service import (
    submit_comment, update_comment, get_comments,
    get_flagged_comments, delete_comment,
)

router = APIRouter()


@router.post("/{landmark_id}", response_model=CommentResponse, status_code=201)
async def add_comment(
    landmark_id: str,
    payload: CommentCreate,
    _: str = Depends(get_current_user),
    db=Depends(get_db),
):
    result = await submit_comment(db, landmark_id, payload)
    if not result:
        raise HTTPException(status_code=404, detail="Landmark not found")
    return result


@router.patch("/{comment_id}", response_model=CommentResponse)
async def edit_comment(
    comment_id: str,
    payload: CommentCreate,
    _: str = Depends(get_current_user),
    db=Depends(get_db),
):
    """Replace an existing comment (re-review). Client tracks comment ID locally."""
    result = await update_comment(db, comment_id, payload)
    if not result:
        raise HTTPException(status_code=404, detail="Comment not found")
    return result


@router.get("/{landmark_id}", response_model=list[CommentResponse])
async def list_comments(landmark_id: str, db=Depends(get_db)):
    return await get_comments(db, landmark_id)


# Admin

@router.get("/admin/flagged", response_model=list[CommentResponse])
async def flagged_comments(_=Depends(get_admin_user), db=Depends(get_db)):
    return await get_flagged_comments(db)


@router.post("/admin/{comment_id}/approve", status_code=204)
async def approve_comment(comment_id: str, _=Depends(get_admin_user), db=Depends(get_db)):
    from bson import ObjectId
    result = await db.comments.update_one(
        {"_id": ObjectId(comment_id)}, {"$set": {"flagged": False}}
    )
    if result.modified_count == 0:
        raise HTTPException(status_code=404, detail="Comment not found")


@router.delete("/admin/{comment_id}", status_code=204)
async def remove_comment(comment_id: str, _=Depends(get_admin_user), db=Depends(get_db)):
    ok = await delete_comment(db, comment_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Comment not found")
