from bson import ObjectId
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from app.core.security import decode_token
from app.core.database import get_database, get_redis as _get_redis

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")
_optional_oauth2 = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


async def get_current_user(token: str = Depends(oauth2_scheme)):
    user_id = decode_token(token)
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return user_id


async def get_optional_user(token: str | None = Depends(_optional_oauth2)) -> str | None:
    if not token:
        return None
    return decode_token(token)


async def get_admin_user(user_id: str = Depends(get_current_user), db=Depends(get_database)):
    doc = await db.users.find_one({"_id": ObjectId(user_id)})
    if not doc or not doc.get("is_admin", False):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return user_id


def get_db():
    return get_database()


def get_redis():
    return _get_redis()
