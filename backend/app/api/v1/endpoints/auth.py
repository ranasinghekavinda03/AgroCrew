from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.auth import LoginRequest, LoginResponse, UserCreate, UserResponse
from app.services.auth_service import (
    AuthenticationServiceError,
    DuplicateEmailError,
    InvalidCredentialsError,
    RegistrationError,
    authenticate_user,
    register_user,
)


router = APIRouter(prefix="/auth")


@router.post(
    "/register",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(registration: UserCreate, db: Session = Depends(get_db)) -> UserResponse:
    try:
        user = register_user(db, registration)
    except DuplicateEmailError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists.",
        ) from None
    except RegistrationError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to create the account.",
        ) from None

    return UserResponse.model_validate(user)


@router.post("/login", response_model=LoginResponse)
def login(credentials: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    try:
        return authenticate_user(db, credentials)
    except InvalidCredentialsError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except AuthenticationServiceError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to authenticate at this time.",
        ) from None
