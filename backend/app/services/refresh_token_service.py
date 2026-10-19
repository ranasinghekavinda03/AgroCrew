from datetime import datetime, timedelta, timezone
import hashlib
import secrets

from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token
from app.db.models.refresh_token import RefreshToken
from app.db.models.user import User
from app.schemas.auth import LoginResponse


REFRESH_TOKEN_BYTES = 32


class InvalidRefreshTokenError(Exception):
    pass


class RefreshTokenServiceError(Exception):
    pass


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_token_pair(db: Session, user_id: int) -> LoginResponse:
    now = datetime.now(timezone.utc)
    raw_token, stored_token = _new_refresh_token(user_id, now)
    try:
        db.add(stored_token)
        access_token = create_access_token(user_id)
        db.commit()
    except Exception:
        db.rollback()
        raise RefreshTokenServiceError from None

    return _token_response(access_token, raw_token)


def rotate_refresh_token(db: Session, raw_token: str) -> LoginResponse:
    now = datetime.now(timezone.utc)
    supplied_hash = hash_refresh_token(raw_token)
    try:
        result = db.execute(
            select(RefreshToken, User)
            .join(User, User.id == RefreshToken.user_id)
            .where(
                RefreshToken.token_hash == supplied_hash,
                RefreshToken.revoked_at.is_(None),
                RefreshToken.expires_at > now,
                User.is_active.is_(True),
            )
            .with_for_update(of=RefreshToken)
        ).one_or_none()
        if result is None:
            db.rollback()
            raise InvalidRefreshTokenError

        stored_token, user = result
        stored_token.revoked_at = now
        new_raw_token, new_stored_token = _new_refresh_token(user.id, now)
        db.add(new_stored_token)
        access_token = create_access_token(user.id, token_id=secrets.token_hex(16))
        db.commit()
        return _token_response(access_token, new_raw_token)
    except InvalidRefreshTokenError:
        raise
    except SQLAlchemyError:
        db.rollback()
        raise RefreshTokenServiceError from None
    except Exception:
        db.rollback()
        raise RefreshTokenServiceError from None


def revoke_refresh_token(db: Session, raw_token: str) -> None:
    """Idempotently revoke one active refresh token.

    The row lock serializes logout with another logout or refresh. If logout wins,
    refresh observes the revocation and fails. If rotation wins, it consumes this
    token first; logout then becomes a no-op and does not revoke the successor.
    """
    now = datetime.now(timezone.utc)
    supplied_hash = hash_refresh_token(raw_token)
    try:
        stored_token = db.scalar(
            select(RefreshToken)
            .where(
                RefreshToken.token_hash == supplied_hash,
                RefreshToken.revoked_at.is_(None),
                RefreshToken.expires_at > now,
            )
            .with_for_update()
        )
        if stored_token is not None:
            stored_token.revoked_at = now
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        raise RefreshTokenServiceError from None
    except Exception:
        db.rollback()
        raise RefreshTokenServiceError from None


def _new_refresh_token(
    user_id: int,
    now: datetime,
) -> tuple[str, RefreshToken]:
    raw_token = generate_refresh_token()
    return raw_token, RefreshToken(
        user_id=user_id,
        token_hash=hash_refresh_token(raw_token),
        created_at=now,
        expires_at=now + timedelta(days=settings.refresh_token_expire_days),
    )


def _token_response(access_token: str, refresh_token: str) -> LoginResponse:
    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_expire_minutes * 60,
        refresh_expires_in=settings.refresh_token_expire_days * 24 * 60 * 60,
    )
