from fastapi import APIRouter

from app.api.v1.endpoints import auth, farms, health

api_router = APIRouter()

api_router.include_router(
    auth.router,
    tags=["Authentication"],
)

api_router.include_router(
    farms.router,
    tags=["Farms"],
)

api_router.include_router(
    health.router,
    tags=["Health"],
)
