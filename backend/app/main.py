from fastapi import FastAPI

from app.api.v1.router import api_router

app = FastAPI(
    title="AgroCrew API",
    description="Backend API for the AgroCrew Smart Farming Assistant",
    version="0.1.0",
)

app.include_router(
    api_router,
    prefix="/api/v1",
)


@app.get("/")
async def root():
    return {
        "name": "AgroCrew API",
        "status": "running",
    }
