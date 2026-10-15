from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import settings
from app.core.security import create_access_token, hash_password
from app.db.models.user import User


PASSWORD = "StrongTestPassword123!"
AUTHENTICATION_ERROR = {"detail": "Could not validate credentials."}


def register_and_login(
    client: TestClient,
    *,
    name: str = "Test Farmer",
    email: str = "farmer@example.com",
) -> tuple[dict[str, object], str]:
    registration_response = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": PASSWORD},
    )
    assert registration_response.status_code == 201
    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": PASSWORD},
    )
    assert login_response.status_code == 200
    return registration_response.json(), login_response.json()["access_token"]


def authorization(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def encode_claims(**overrides: object) -> str:
    now = datetime.now(timezone.utc)
    claims: dict[str, object] = {
        "sub": "1",
        "iat": now,
        "exp": now + timedelta(minutes=30),
        "token_type": "access",
    }
    claims.update(overrides)
    return jwt.encode(
        claims,
        settings.jwt_secret_key.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )


def assert_authentication_error(response: object) -> None:
    assert response.status_code == 401
    assert response.json() == AUTHENTICATION_ERROR
    assert response.headers["www-authenticate"] == "Bearer"


def test_valid_token_returns_authenticated_users_safe_profile(
    client: TestClient,
) -> None:
    registered, token = register_and_login(client)

    response = client.get("/api/v1/auth/me", headers=authorization(token))

    assert response.status_code == 200
    profile = response.json()
    assert profile == registered
    assert set(profile) == {
        "id",
        "name",
        "email",
        "preferred_language",
        "is_active",
        "created_at",
    }
    assert "password" not in response.text.lower()
    assert "password_hash" not in response.text.lower()
    assert token not in response.text
    assert settings.jwt_secret_key.get_secret_value() not in response.text


def test_missing_authorization_header_returns_401(client: TestClient) -> None:
    assert_authentication_error(client.get("/api/v1/auth/me"))


@pytest.mark.parametrize(
    "header",
    [
        "Basic credentials",
        "Token credentials",
        "Bearer",
        "Bearer ",
    ],
)
def test_invalid_authorization_scheme_returns_401(
    client: TestClient,
    header: str,
) -> None:
    response = client.get("/api/v1/auth/me", headers={"Authorization": header})
    assert_authentication_error(response)


def test_malformed_token_returns_401(client: TestClient) -> None:
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization("not-a-jwt"))
    )


def test_expired_token_returns_401(client: TestClient) -> None:
    registered, _ = register_and_login(client)
    token = create_access_token(
        registered["id"],
        now=datetime.now(timezone.utc) - timedelta(minutes=31),
    )
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_tampered_token_returns_401(client: TestClient) -> None:
    _, token = register_and_login(client)
    header, payload, signature = token.split(".")
    replacement = "A" if signature[0] != "A" else "B"
    tampered = ".".join((header, payload, replacement + signature[1:]))
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(tampered))
    )


def test_wrong_token_type_returns_401(client: TestClient) -> None:
    registered, _ = register_and_login(client)
    token = encode_claims(sub=str(registered["id"]), token_type="refresh")
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_missing_subject_returns_401(client: TestClient) -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "iat": now,
            "exp": now + timedelta(minutes=30),
            "token_type": "access",
        },
        settings.jwt_secret_key.get_secret_value(),
        algorithm=settings.jwt_algorithm,
    )
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


@pytest.mark.parametrize("subject", ["", "abc", "0", "-1", "1.0", "01"])
def test_invalid_subject_returns_401(client: TestClient, subject: str) -> None:
    token = encode_claims(sub=subject)
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_token_for_nonexistent_user_returns_401(client: TestClient) -> None:
    token = create_access_token(999_999_999)
    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_token_for_deleted_user_returns_401(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, token = register_and_login(client)
    with test_session_factory() as db:
        db.execute(delete(User).where(User.id == registered["id"]))
        db.commit()

    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_inactive_user_returns_401(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = User(
            name="Inactive Farmer",
            email="inactive@example.com",
            password_hash=hash_password(PASSWORD),
            is_active=False,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        token = create_access_token(user.id)

    assert_authentication_error(
        client.get("/api/v1/auth/me", headers=authorization(token))
    )


def test_two_users_can_only_retrieve_their_own_profiles(client: TestClient) -> None:
    user_a, token_a = register_and_login(
        client,
        name="Farmer A",
        email="farmer-a@example.com",
    )
    user_b, token_b = register_and_login(
        client,
        name="Farmer B",
        email="farmer-b@example.com",
    )

    profile_a = client.get("/api/v1/auth/me", headers=authorization(token_a))
    profile_b = client.get("/api/v1/auth/me", headers=authorization(token_b))

    assert profile_a.status_code == 200
    assert profile_b.status_code == 200
    assert profile_a.json() == user_a
    assert profile_b.json() == user_b
    assert profile_a.json()["id"] != profile_b.json()["id"]


def test_openapi_documents_bearer_security_without_oauth_form_login(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    me_operation = schema["paths"]["/api/v1/auth/me"]["get"]
    security_schemes = schema["components"]["securitySchemes"]

    assert me_operation["security"] == [{"HTTPBearer": []}]
    assert security_schemes["HTTPBearer"] == {
        "type": "http",
        "scheme": "bearer",
    }
    login_operation = schema["paths"]["/api/v1/auth/login"]["post"]
    assert "application/json" in login_operation["requestBody"]["content"]
    assert "security" not in login_operation
