from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.db.models.user import User
from app.db.session import get_db
from app.schemas.auth import (
    LoginRequest,
    LoginResponse,
    LogoutRequest,
    RefreshRequest,
    UserCreate,
    UserResponse,
)
from app.services.auth_service import (
    AuthenticationServiceError,
    DuplicateEmailError,
    InvalidCredentialsError,
    RegistrationError,
    authenticate_user,
    register_user,
)
from app.services.refresh_token_service import (
    InvalidRefreshTokenError,
    RefreshTokenServiceError,
    revoke_refresh_token,
    rotate_refresh_token,
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


@router.post("/refresh", response_model=LoginResponse)
def refresh_tokens(
    request: RefreshRequest,
    db: Session = Depends(get_db),
) -> LoginResponse:
    try:
        return rotate_refresh_token(db, request.refresh_token)
    except InvalidRefreshTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from None
    except RefreshTokenServiceError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to refresh authentication at this time.",
        ) from None


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    responses={204: {"description": "Refresh token revoked or already inactive."}},
    summary="Log out the supplied refresh-token session",
    description=(
        "Revokes the supplied refresh token without requiring an access token. "
        "The operation is idempotent. Existing stateless access JWTs remain valid "
        "until their expiration."
    ),
)
def logout(request: LogoutRequest, db: Session = Depends(get_db)) -> Response:
    try:
        revoke_refresh_token(db, request.refresh_token)
    except RefreshTokenServiceError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to log out at this time.",
        ) from None

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserResponse)
def current_user_profile(
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    return UserResponse.model_validate(current_user)
