from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.api.v1.endpoints import auth
from app.core.security import verify_password
from app.db.models.user import User
from app.schemas.auth import UserCreate
from app.services.auth_service import (
    DuplicateEmailError,
    RegistrationError,
    register_user,
)


VALID_REGISTRATION = {
    "name": "  Test Farmer  ",
    "email": "Farmer@Example.COM",
    "password": "StrongTestPassword123!",
}


def test_successful_registration_persists_a_safe_user(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    response = client.post("/api/v1/auth/register", json=VALID_REGISTRATION)

    assert response.status_code == 201
    body = response.json()
    assert set(body) == {
        "id",
        "name",
        "email",
        "preferred_language",
        "is_active",
        "created_at",
    }
    assert body["name"] == "Test Farmer"
    assert body["email"] == "farmer@example.com"
    assert body["preferred_language"] == "English"
    assert body["is_active"] is True
    assert body["created_at"]
    assert "password" not in body
    assert "password_hash" not in body

    with test_session_factory() as db:
        user = db.scalar(select(User).where(User.email == "farmer@example.com"))

    assert user is not None
    assert user.password_hash.startswith("$argon2")
    assert user.password_hash != VALID_REGISTRATION["password"]
    assert VALID_REGISTRATION["password"] not in user.password_hash
    assert verify_password(VALID_REGISTRATION["password"], user.password_hash)
    assert not verify_password("IncorrectPassword123!", user.password_hash)


def test_duplicate_email_returns_conflict(client: TestClient) -> None:
    first_response = client.post(
        "/api/v1/auth/register",
        json={**VALID_REGISTRATION, "email": "farmer@example.com"},
    )
    duplicate_response = client.post(
        "/api/v1/auth/register",
        json={**VALID_REGISTRATION, "email": "farmer@example.com"},
    )

    assert first_response.status_code == 201
    assert duplicate_response.status_code == 409
    assert duplicate_response.json() == {
        "detail": "An account with this email already exists."
    }


def test_duplicate_email_is_case_insensitive(client: TestClient) -> None:
    first_response = client.post(
        "/api/v1/auth/register",
        json={**VALID_REGISTRATION, "email": "CaseSensitive@Example.com"},
    )
    duplicate_response = client.post(
        "/api/v1/auth/register",
        json={**VALID_REGISTRATION, "email": "casesensitive@example.COM"},
    )

    assert first_response.status_code == 201
    assert duplicate_response.status_code == 409


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("email", "not-an-email"),
        ("name", "   "),
        ("password", "TooShort1!"),
        ("password", "x" * 129),
    ],
)
def test_invalid_registration_returns_validation_error(
    client: TestClient,
    field: str,
    value: str,
) -> None:
    response = client.post(
        "/api/v1/auth/register",
        json={**VALID_REGISTRATION, field: value},
    )

    assert response.status_code == 422


def test_non_unique_database_constraint_failure_is_safely_wrapped() -> None:
    db = MagicMock(spec=Session)
    db.scalar.return_value = None
    db.commit.side_effect = IntegrityError(
        "INSERT INTO users",
        {},
        Exception("another database constraint failed"),
    )
    registration = UserCreate(**VALID_REGISTRATION)

    with pytest.raises(RegistrationError):
        register_user(db, registration)

    db.rollback.assert_called_once_with()


def test_concurrent_email_unique_violation_is_a_duplicate() -> None:
    db = MagicMock(spec=Session)
    db.scalar.return_value = None
    db.commit.side_effect = IntegrityError(
        "INSERT INTO users",
        {},
        Exception("UNIQUE constraint failed: users.email"),
    )
    registration = UserCreate(**VALID_REGISTRATION)

    with pytest.raises(DuplicateEmailError):
        register_user(db, registration)

    db.rollback.assert_called_once_with()


def test_unexpected_registration_failure_returns_safe_error(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail_registration(*args: object, **kwargs: object) -> None:
        raise RegistrationError

    monkeypatch.setattr(auth, "register_user", fail_registration)

    response = client.post("/api/v1/auth/register", json=VALID_REGISTRATION)

    assert response.status_code == 500
    assert response.json() == {"detail": "Unable to create the account."}


def test_health_endpoint_still_works(client: TestClient) -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "agrocrew-api"}
