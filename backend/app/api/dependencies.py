import jwt
from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.security import decode_access_token
from app.db.models.user import User
from app.db.session import get_db


bearer_scheme = HTTPBearer(auto_error=False)


def _authentication_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _authentication_error()

    try:
        claims = decode_access_token(credentials.credentials)
        subject = claims["sub"]
        user_id = int(subject)
        if user_id <= 0 or str(user_id) != subject:
            raise ValueError
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        raise _authentication_error() from None

    try:
        user = db.get(User, user_id)
    except SQLAlchemyError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to authenticate at this time.",
        ) from None

    if user is None or not user.is_active:
        raise _authentication_error()
    return user
