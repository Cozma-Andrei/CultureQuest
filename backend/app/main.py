from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.core.config import settings
from app.core.database import connect_db, close_db
from app.api.routes import auth, landmarks, routes, quests, federated, users


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect_db()
    yield
    await close_db()


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(landmarks.router, prefix="/api/landmarks", tags=["landmarks"])
app.include_router(routes.router, prefix="/api/routes", tags=["routes"])
app.include_router(quests.router, prefix="/api/quests", tags=["quests"])
app.include_router(federated.router, prefix="/api/federated", tags=["federated"])
app.include_router(users.router, prefix="/api/users", tags=["users"])


@app.get("/health")
async def health():
    return {"status": "ok", "version": settings.app_version}
