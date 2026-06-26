from fastapi import APIRouter, Depends, HTTPException, status
from app.api.deps import get_current_user, get_optional_user, get_admin_user, get_db
from app.models.landmark import LandmarkCreate, LandmarkResponse, RatingPayload, LandmarkSubmit, LandmarkEdit, StorySubmit, StoryResponse
from app.services.landmark_service import (
    get_nearby_landmarks, get_all_landmarks, get_landmark_by_id, create_landmark,
    seed_landmarks, record_visit, rate_landmark, submit_landmark,
    get_pending_landmarks, get_all_submissions, approve_landmark, reject_landmark,
    edit_landmark, delete_landmark,
    submit_story, get_pending_stories, get_pending_stories_for_owner, approve_story, reject_story,
)

router = APIRouter()


@router.get("/", response_model=list[LandmarkResponse])
async def list_landmarks(lat: float, lng: float, radius_m: int = 1500, db=Depends(get_db)):
    return await get_nearby_landmarks(db, lat, lng, radius_m)


@router.get("/all", response_model=list[LandmarkResponse])
async def list_all_landmarks(db=Depends(get_db)):
    return await get_all_landmarks(db)


@router.get("/admin/pending", response_model=list[LandmarkResponse])
async def pending_landmarks_get(_=Depends(get_admin_user), db=Depends(get_db)):
    return await get_pending_landmarks(db)


@router.get("/admin/submissions", response_model=list[LandmarkResponse])
async def all_submissions(_=Depends(get_admin_user), db=Depends(get_db)):
    return await get_all_submissions(db)


@router.get("/admin/pending-stories", response_model=list[StoryResponse])
async def pending_stories_get(_=Depends(get_admin_user), db=Depends(get_db)):
    return await get_pending_stories(db)


@router.get("/{landmark_id}", response_model=LandmarkResponse)
async def get_landmark(landmark_id: str, db=Depends(get_db)):
    landmark = await get_landmark_by_id(db, landmark_id)
    if not landmark:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return landmark


@router.post("/", response_model=LandmarkResponse)
async def add_landmark(payload: LandmarkCreate, user=Depends(get_current_user), db=Depends(get_db)):
    return await create_landmark(db, payload)


@router.post("/seed", response_model=list[LandmarkResponse])
async def seed(lat: float, lng: float, user_id=Depends(get_current_user), db=Depends(get_db)):
    """Dev endpoint: insert sample landmarks around the given coordinate, attributed to the caller."""
    return await seed_landmarks(db, lat, lng, user_id=user_id)


async def _check_submitter_or_admin(db, landmark_id: str, user_id: str):
    """Returns the landmark or raises 403/404."""
    lm = await get_landmark_by_id(db, landmark_id)
    if not lm:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    user_doc = await db.users.find_one({"_id": __import__("bson").ObjectId(user_id)})
    is_admin = user_doc.get("is_admin", False) if user_doc else False
    if not is_admin and lm.submitted_by != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only the submitter or an admin can update this landmark")
    return lm


@router.patch("/{landmark_id}/website", response_model=LandmarkResponse)
async def set_website(
    landmark_id: str,
    payload: LandmarkEdit,
    user_id=Depends(get_current_user),
    db=Depends(get_db),
):
    """Set or update the website for a landmark (submitter or admin only)."""
    await _check_submitter_or_admin(db, landmark_id, user_id)
    return await edit_landmark(db, landmark_id, payload)


@router.patch("/{landmark_id}/info", response_model=LandmarkResponse)
async def set_info(
    landmark_id: str,
    payload: LandmarkEdit,
    user_id=Depends(get_current_user),
    db=Depends(get_db),
):
    """Set or update opening hours, ticket price, and discount info (submitter or admin only)."""
    await _check_submitter_or_admin(db, landmark_id, user_id)
    return await edit_landmark(db, landmark_id, payload)


@router.post("/{landmark_id}/visit", status_code=204)
async def visit(landmark_id: str, db=Depends(get_db)):
    """Anonymous visit counter: no user identity stored."""
    await record_visit(db, landmark_id)


@router.post("/{landmark_id}/rate", response_model=LandmarkResponse)
async def rate(landmark_id: str, payload: RatingPayload, db=Depends(get_db)):
    if not (1 <= payload.rating <= 5):
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Rating must be 1–5")
    result = await rate_landmark(db, landmark_id, payload.rating, payload.previous_rating)
    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return result


@router.post("/submit", response_model=LandmarkResponse, status_code=201)
async def submit(payload: LandmarkSubmit, user_id=Depends(get_current_user), db=Depends(get_db)):
    """Users can suggest a new landmark; it goes into pending review."""
    return await submit_landmark(db, payload, user_id)


# Admin endpoints

@router.post("/admin/{landmark_id}/approve", response_model=LandmarkResponse)
async def approve(landmark_id: str, _=Depends(get_admin_user), db=Depends(get_db)):
    result = await approve_landmark(db, landmark_id)
    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return result


@router.post("/admin/{landmark_id}/reject", status_code=204)
async def reject(landmark_id: str, _=Depends(get_admin_user), db=Depends(get_db)):
    ok = await reject_landmark(db, landmark_id)
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")


@router.patch("/admin/{landmark_id}", response_model=LandmarkResponse)
async def admin_edit(landmark_id: str, payload: LandmarkEdit, _=Depends(get_admin_user), db=Depends(get_db)):
    result = await edit_landmark(db, landmark_id, payload)
    if not result:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")
    return result


@router.delete("/admin/{landmark_id}", status_code=204)
async def admin_delete(landmark_id: str, _=Depends(get_admin_user), db=Depends(get_db)):
    ok = await delete_landmark(db, landmark_id)
    if not ok:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Landmark not found")


# Story endpoints

@router.post("/{landmark_id}/stories", response_model=StoryResponse, status_code=201)
async def add_story(landmark_id: str, payload: StorySubmit, user_id=Depends(get_current_user), db=Depends(get_db)):
    if not payload.text.strip():
        raise HTTPException(status_code=422, detail="Story text cannot be empty")
    result = await submit_story(db, landmark_id, user_id, payload.text)
    if not result:
        raise HTTPException(status_code=404, detail="Landmark not found")
    return result


@router.get("/owner/pending-stories", response_model=list[StoryResponse])
async def pending_stories_owner(user_id: str = Depends(get_current_user), db=Depends(get_db)):
    return await get_pending_stories_for_owner(db, user_id)


async def _check_admin_or_story_landmark_owner(db, story_id: str, user_id: str):
    user_doc = await db.users.find_one({"_id": __import__("bson").ObjectId(user_id)})
    if user_doc and user_doc.get("is_admin", False):
        return
    story = await db.stories.find_one({"_id": __import__("bson").ObjectId(story_id)})
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    lm = await db.landmarks.find_one({"_id": __import__("bson").ObjectId(story["landmark_id"])})
    if not lm or lm.get("submitted_by") != user_id:
        raise HTTPException(status_code=403, detail="Admin or landmark creator access required")


@router.post("/admin/stories/{story_id}/approve", status_code=204)
async def approve_story_ep(story_id: str, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    await _check_admin_or_story_landmark_owner(db, story_id, user_id)
    ok = await approve_story(db, story_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Story not found")


@router.post("/admin/stories/{story_id}/reject", status_code=204)
async def reject_story_ep(story_id: str, user_id: str = Depends(get_current_user), db=Depends(get_db)):
    await _check_admin_or_story_landmark_owner(db, story_id, user_id)
    ok = await reject_story(db, story_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Story not found")
