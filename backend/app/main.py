from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import api_router
from app.core.config import settings

app = FastAPI(
    title="AgroCrew API",
    description="Backend API for the AgroCrew Smart Farming Assistant",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Content-Type", "Authorization"],
)

app.include_router(
    api_router,
    prefix="/api/v1",
)


@app.exception_handler(RequestValidationError)
async def sanitized_validation_error(
    _request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    errors = [
        {key: value for key, value in error.items() if key != "input"}
        for error in exc.errors()
    ]
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content=jsonable_encoder({"detail": errors}),
    )


@app.get("/")
async def root():
    return {
        "name": "AgroCrew API",
        "status": "running",
    }
