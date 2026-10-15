from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from pwdlib import PasswordHash

from app.core.config import settings


password_hash = PasswordHash.recommended()

ACCESS_TOKEN_TYPE = "access"
REQUIRED_ACCESS_TOKEN_CLAIMS = ["sub", "iat", "exp", "token_type"]


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, hashed_password: str) -> bool:
    return password_hash.verify(password, hashed_password)


def create_access_token(
    subject: int | str,
    *,
    now: datetime | None = None,
) -> str:
    issued_at = now or datetime.now(timezone.utc)
    if issued_at.tzinfo is None:
        raise ValueError("Token timestamps must be timezone-aware.")
    expires_at = issued_at + timedelta(minutes=settings.access_token_expire_minutes)
    claims = {
        "sub": str(subject),
        "iat": issued_at,
        "exp": expires_at,
        "token_type": ACCESS_TOKEN_TYPE,
    }
    return jwt.encode(
        claims,
        settings.jwt_secret_key.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> dict[str, Any]:
    claims = jwt.decode(
        token,
        settings.jwt_secret_key.get_secret_value(),
        algorithms=[settings.jwt_algorithm],
        options={"require": REQUIRED_ACCESS_TOKEN_CLAIMS},
    )
    if claims.get("token_type") != ACCESS_TOKEN_TYPE:
        raise jwt.InvalidTokenError("Token is not an access token.")
    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject:
        raise jwt.InvalidTokenError("Token subject is invalid.")
    return claims


def get_access_token_subject(token: str) -> str:
    return decode_access_token(token)["sub"]
