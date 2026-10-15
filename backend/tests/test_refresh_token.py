from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import jwt
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import Settings, settings
from app.core.security import decode_access_token
from app.db.models.refresh_token import RefreshToken
from app.db.models.user import User
from app.services.refresh_token_service import (
    RefreshTokenServiceError,
    generate_refresh_token,
    hash_refresh_token,
    rotate_refresh_token,
)


PASSWORD = "StrongTestPassword123!"
EMAIL = "refresh-farmer@example.com"
INVALID_REFRESH_ERROR = {"detail": "Invalid refresh token."}


def register_and_login(client: TestClient) -> tuple[dict[str, object], dict[str, object]]:
    registration = client.post(
        "/api/v1/auth/register",
        json={"name": "Refresh Farmer", "email": EMAIL, "password": PASSWORD},
    )
    assert registration.status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={"email": EMAIL, "password": PASSWORD},
    )
    assert login.status_code == 200
    return registration.json(), login.json()


def assert_invalid_refresh(response: object, supplied_token: str | None = None) -> None:
    assert response.status_code == 401
    assert response.json() == INVALID_REFRESH_ERROR
    assert response.headers["www-authenticate"] == "Bearer"
    if supplied_token is not None:
        assert supplied_token not in response.text
        assert hash_refresh_token(supplied_token) not in response.text


def test_login_persists_only_refresh_token_hash(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, login = register_and_login(client)
    raw_token = login["refresh_token"]

    with test_session_factory() as db:
        stored = db.scalar(
            select(RefreshToken).where(RefreshToken.user_id == registered["id"])
        )

    assert stored is not None
    assert stored.token_hash == hash_refresh_token(raw_token)
    assert stored.token_hash != raw_token
    assert raw_token not in stored.token_hash
    assert len(stored.token_hash) == 64
    assert stored.revoked_at is None
    assert stored.expires_at - stored.created_at == timedelta(days=7)
    assert login["token_type"] == "bearer"
    assert login["expires_in"] == 1800
    assert login["refresh_expires_in"] == 604800
    assert "password" not in str(login).lower()


def test_refresh_rotates_tokens_atomically(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, login = register_and_login(client)

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )

    assert response.status_code == 200
    refreshed = response.json()
    assert refreshed["access_token"] != login["access_token"]
    assert refreshed["refresh_token"] != login["refresh_token"]
    assert refreshed["token_type"] == "bearer"
    assert refreshed["expires_in"] == 1800
    assert refreshed["refresh_expires_in"] == 604800
    claims = decode_access_token(refreshed["access_token"])
    assert claims["sub"] == str(registered["id"])

    with test_session_factory() as db:
        old_token = db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hash_refresh_token(login["refresh_token"])
            )
        )
        new_token = db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hash_refresh_token(
                    refreshed["refresh_token"]
                )
            )
        )
    assert old_token is not None and old_token.revoked_at is not None
    assert new_token is not None and new_token.revoked_at is None
    assert old_token.user_id == new_token.user_id == registered["id"]


def test_rotated_token_cannot_be_reused(client: TestClient) -> None:
    _, login = register_and_login(client)
    first_refresh = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert first_refresh.status_code == 200

    reused = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert_invalid_refresh(reused, login["refresh_token"])


def test_expired_token_returns_401(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)
    with test_session_factory() as db:
        stored = db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hash_refresh_token(login["refresh_token"])
            )
        )
        assert stored is not None
        stored.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert_invalid_refresh(response, login["refresh_token"])


def test_revoked_token_returns_401(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)
    with test_session_factory() as db:
        stored = db.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash == hash_refresh_token(login["refresh_token"])
            )
        )
        assert stored is not None
        stored.revoked_at = datetime.now(timezone.utc)
        db.commit()

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert_invalid_refresh(response, login["refresh_token"])


def test_invalid_random_token_returns_401(client: TestClient) -> None:
    token = generate_refresh_token()
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": token},
    )
    assert_invalid_refresh(response, token)


@pytest.mark.parametrize("payload", [{}, {"refresh_token": ""}, {"refresh_token": "   "}])
def test_missing_or_empty_refresh_token_returns_422(
    client: TestClient,
    payload: dict[str, str],
) -> None:
    assert client.post("/api/v1/auth/refresh", json=payload).status_code == 422


def test_inactive_user_cannot_refresh(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, login = register_and_login(client)
    with test_session_factory() as db:
        user = db.get(User, registered["id"])
        assert user is not None
        user.is_active = False
        db.commit()

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert_invalid_refresh(response, login["refresh_token"])


def test_deleted_user_cannot_refresh(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, login = register_and_login(client)
    with test_session_factory() as db:
        user = db.get(User, registered["id"])
        assert user is not None
        db.delete(user)
        db.commit()

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert_invalid_refresh(response, login["refresh_token"])


def test_database_failure_rolls_back() -> None:
    db = MagicMock(spec=Session)
    db.execute.side_effect = SQLAlchemyError("database unavailable")

    with pytest.raises(RefreshTokenServiceError):
        rotate_refresh_token(db, generate_refresh_token())

    db.rollback.assert_called_once_with()


def test_refresh_token_has_at_least_256_bits_of_randomness() -> None:
    first = generate_refresh_token()
    second = generate_refresh_token()
    assert first != second
    assert len(first) >= 43


@pytest.mark.parametrize("days", [0, -1, 366])
def test_invalid_refresh_lifetime_is_rejected(days: int) -> None:
    with pytest.raises(ValidationError):
        Settings(
            _env_file=None,
            database_url="sqlite://",
            jwt_secret_key="a-secure-test-secret-that-is-at-least-32-bytes",
            refresh_token_expire_days=days,
        )


def test_refresh_access_token_remains_a_normal_access_jwt(client: TestClient) -> None:
    _, login = register_and_login(client)
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )
    assert response.status_code == 200
    claims = decode_access_token(response.json()["access_token"])
    assert claims["token_type"] == "access"
    assert claims["exp"] - claims["iat"] == 1800
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(response.json()["refresh_token"])


def test_openapi_documents_json_refresh_without_access_token_authentication(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/api/v1/auth/refresh"]["post"]
    assert "application/json" in operation["requestBody"]["content"]
    assert "security" not in operation
