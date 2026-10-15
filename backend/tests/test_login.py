from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

import jwt
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.api.v1.endpoints import auth
from app.core.config import Settings, settings
from app.core.security import (
    create_access_token,
    decode_access_token,
    get_access_token_subject,
    hash_password,
)
from app.db.models.user import User
from app.services.auth_service import AuthenticationServiceError


PASSWORD = "StrongTestPassword123!"
LOGIN_EMAIL = "farmer@example.com"


def register_user(client: TestClient, email: str = LOGIN_EMAIL) -> dict[str, object]:
    response = client.post(
        "/api/v1/auth/register",
        json={"name": "Test Farmer", "email": email, "password": PASSWORD},
    )
    assert response.status_code == 201
    return response.json()


def test_login_returns_a_valid_signed_access_token(client: TestClient) -> None:
    registered = register_user(client)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": LOGIN_EMAIL, "password": PASSWORD},
    )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {
        "access_token",
        "refresh_token",
        "token_type",
        "expires_in",
        "refresh_expires_in",
    }
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 1800
    assert body["refresh_expires_in"] == 604800
    assert body["refresh_token"]
    assert "password" not in body
    assert "password_hash" not in body

    claims = decode_access_token(body["access_token"])
    assert claims["sub"] == str(registered["id"])
    assert claims["token_type"] == "access"
    assert set(("sub", "iat", "exp", "token_type")).issubset(claims)
    assert claims["exp"] - claims["iat"] == 1800
    assert get_access_token_subject(body["access_token"]) == str(registered["id"])
    assert all("password" not in key.lower() for key in claims)
    assert PASSWORD not in str(claims)


def test_login_normalizes_email(client: TestClient) -> None:
    register_user(client)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": "  FARMER@EXAMPLE.COM  ", "password": PASSWORD},
    )

    assert response.status_code == 200


@pytest.mark.parametrize(
    "payload",
    [
        {"email": LOGIN_EMAIL},
        {"password": PASSWORD},
        {"email": "not-an-email", "password": PASSWORD},
        {"email": LOGIN_EMAIL, "password": ""},
        {"email": LOGIN_EMAIL, "password": "   "},
    ],
)
def test_invalid_login_input_returns_422(
    client: TestClient,
    payload: dict[str, str],
) -> None:
    response = client.post("/api/v1/auth/login", json=payload)
    assert response.status_code == 422


@pytest.mark.parametrize(
    ("email", "password"),
    [
        (LOGIN_EMAIL, "IncorrectPassword123!"),
        ("missing@example.com", PASSWORD),
    ],
)
def test_invalid_credentials_return_same_401_without_changing_users(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
    email: str,
    password: str,
) -> None:
    registered = register_user(client)
    with test_session_factory() as db:
        before_count = db.scalar(select(func.count()).select_from(User))
        before_user = db.get(User, registered["id"])
        assert before_user is not None
        before_values = (before_user.email, before_user.password_hash, before_user.is_active)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password."}
    assert response.headers["www-authenticate"] == "Bearer"
    with test_session_factory() as db:
        assert db.scalar(select(func.count()).select_from(User)) == before_count
        after_user = db.get(User, registered["id"])
        assert after_user is not None
        assert (after_user.email, after_user.password_hash, after_user.is_active) == before_values


def test_inactive_user_returns_generic_401(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        db.add(
            User(
                name="Inactive Farmer",
                email=LOGIN_EMAIL,
                password_hash=hash_password(PASSWORD),
                is_active=False,
            )
        )
        db.commit()

    response = client.post(
        "/api/v1/auth/login",
        json={"email": LOGIN_EMAIL, "password": PASSWORD},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password."}
    assert response.headers["www-authenticate"] == "Bearer"


def test_expired_token_is_rejected() -> None:
    token = create_access_token(
        123,
        now=datetime.now(timezone.utc) - timedelta(minutes=31),
    )
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_access_token(token)


def test_tampered_signature_is_rejected() -> None:
    token = create_access_token(123)
    replacement = "A" if token[-1] != "A" else "B"
    tampered = token[:-1] + replacement
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(tampered)


def test_unsupported_algorithm_is_rejected() -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": "123",
            "iat": now,
            "exp": now + timedelta(minutes=30),
            "token_type": "access",
        },
        settings.jwt_secret_key.get_secret_value(),
        algorithm="HS384",
    )
    with pytest.raises(jwt.InvalidAlgorithmError):
        decode_access_token(token)


def test_token_missing_required_claim_is_rejected() -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {"sub": "123", "iat": now, "token_type": "access"},
        settings.jwt_secret_key.get_secret_value(),
        algorithm="HS256",
    )
    with pytest.raises(jwt.MissingRequiredClaimError):
        decode_access_token(token)


def test_wrong_token_type_is_rejected() -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": "123",
            "iat": now,
            "exp": now + timedelta(minutes=30),
            "token_type": "refresh",
        },
        settings.jwt_secret_key.get_secret_value(),
        algorithm="HS256",
    )
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(token)


def test_malformed_token_is_rejected() -> None:
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token("not-a-jwt")


@pytest.mark.parametrize("secret", ["", " " * 32, "too-short"])
def test_missing_empty_or_weak_jwt_secrets_are_rejected(secret: str) -> None:
    with pytest.raises(ValidationError):
        Settings(
            _env_file=None,
            database_url="sqlite://",
            jwt_secret_key=secret,
        )


@pytest.mark.parametrize("minutes", [0, -1, 1441])
def test_invalid_token_expiry_is_rejected(minutes: int) -> None:
    with pytest.raises(ValidationError):
        Settings(
            _env_file=None,
            database_url="sqlite://",
            jwt_secret_key="a-secure-test-secret-that-is-at-least-32-bytes",
            access_token_expire_minutes=minutes,
        )


def test_unexpected_login_failure_returns_safe_500(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail_authentication(*args: object, **kwargs: object) -> None:
        raise AuthenticationServiceError

    monkeypatch.setattr(auth, "authenticate_user", fail_authentication)
    response = client.post(
        "/api/v1/auth/login",
        json={"email": LOGIN_EMAIL, "password": PASSWORD},
    )
    assert response.status_code == 500
    assert response.json() == {"detail": "Unable to authenticate at this time."}


def test_database_failure_is_safely_wrapped() -> None:
    db = MagicMock(spec=Session)
    db.scalar.side_effect = SQLAlchemyError("database unavailable")

    with pytest.raises(AuthenticationServiceError):
        from app.schemas.auth import LoginRequest
        from app.services.auth_service import authenticate_user

        authenticate_user(
            db,
            LoginRequest(email=LOGIN_EMAIL, password=PASSWORD),
        )
