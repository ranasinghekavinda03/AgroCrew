from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from unittest.mock import MagicMock

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.api.v1.endpoints import auth
from app.db.base import Base
from app.db.models.refresh_token import RefreshToken
from app.db.models.user import User
from app.services.refresh_token_service import (
    RefreshTokenServiceError,
    generate_refresh_token,
    hash_refresh_token,
    revoke_refresh_token,
)


PASSWORD = "StrongTestPassword123!"


def register_and_login(
    client: TestClient,
    *,
    email: str = "logout-farmer@example.com",
    name: str = "Logout Farmer",
) -> tuple[dict[str, object], dict[str, object]]:
    registration = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": PASSWORD},
    )
    assert registration.status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": PASSWORD},
    )
    assert login.status_code == 200
    return registration.json(), login.json()


def logout(client: TestClient, refresh_token: str):
    return client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": refresh_token},
    )


def stored_token(db: Session, raw_token: str) -> RefreshToken | None:
    return db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_refresh_token(raw_token)
        )
    )


def test_logout_returns_empty_204_and_revokes_matching_token(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)

    response = logout(client, login["refresh_token"])

    assert response.status_code == 204
    assert response.content == b""
    assert response.headers.get("content-type") is None
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        assert token.revoked_at is not None


def test_logged_out_refresh_token_cannot_be_refreshed(client: TestClient) -> None:
    _, login = register_and_login(client)
    assert logout(client, login["refresh_token"]).status_code == 204

    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid refresh token."}
    assert login["refresh_token"] not in response.text
    assert hash_refresh_token(login["refresh_token"]) not in response.text


def test_repeated_logout_is_idempotent_and_does_not_rewrite_timestamp(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)
    assert logout(client, login["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        first_revoked_at = token.revoked_at

    assert logout(client, login["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        assert token.revoked_at == first_revoked_at


def test_unknown_token_returns_same_empty_204_without_modifying_records(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)

    response = logout(client, generate_refresh_token())

    assert response.status_code == 204
    assert response.content == b""
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        assert token.revoked_at is None


def test_expired_token_logout_is_safe_and_does_not_update_it(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        token.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()

    assert logout(client, login["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        assert token.revoked_at is None


def test_already_revoked_token_logout_is_safe_and_does_not_update_it(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, login = register_and_login(client)
    original_revocation = datetime.now(timezone.utc) - timedelta(minutes=5)
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        token.revoked_at = original_revocation
        db.commit()

    assert logout(client, login["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        token = stored_token(db, login["refresh_token"])
        assert token is not None
        assert token.revoked_at == original_revocation.replace(tzinfo=None)


def test_missing_refresh_token_returns_422(client: TestClient) -> None:
    assert client.post("/api/v1/auth/logout", json={}).status_code == 422


@pytest.mark.parametrize(
    "payload",
    [None, [], {"refresh_token": ""}, {"refresh_token": "   "}, {"refresh_token": 7}],
)
def test_structurally_invalid_logout_body_returns_422(
    client: TestClient,
    payload: object,
) -> None:
    assert client.post("/api/v1/auth/logout", json=payload).status_code == 422


def test_logout_does_not_change_user_or_password_hash(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    registered, login = register_and_login(client)
    with test_session_factory() as db:
        user = db.get(User, registered["id"])
        assert user is not None
        original = (user.name, user.email, user.password_hash, user.is_active)

    assert logout(client, login["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        user = db.get(User, registered["id"])
        assert user is not None
        assert (user.name, user.email, user.password_hash, user.is_active) == original


def test_logout_does_not_affect_another_users_session(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, first = register_and_login(client)
    _, second = register_and_login(
        client,
        email="other-logout-farmer@example.com",
        name="Other Farmer",
    )

    assert logout(client, first["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        other_token = stored_token(db, second["refresh_token"])
        assert other_token is not None
        assert other_token.revoked_at is None
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": second["refresh_token"]},
    )
    assert response.status_code == 200


def test_logout_does_not_affect_a_separate_session_for_same_user(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    _, first = register_and_login(client)
    second_response = client.post(
        "/api/v1/auth/login",
        json={"email": "logout-farmer@example.com", "password": PASSWORD},
    )
    assert second_response.status_code == 200
    second = second_response.json()

    assert logout(client, first["refresh_token"]).status_code == 204
    with test_session_factory() as db:
        second_token = stored_token(db, second["refresh_token"])
        assert second_token is not None
        assert second_token.revoked_at is None
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": second["refresh_token"]},
    )
    assert response.status_code == 200


def test_concurrent_logout_requests_leave_one_consistently_revoked_record(
    tmp_path,
) -> None:
    engine = create_engine(
        f"sqlite+pysqlite:///{tmp_path / 'concurrent-logout.db'}",
        connect_args={"check_same_thread": False, "timeout": 10},
    )
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)
    raw_token = generate_refresh_token()
    with factory() as db:
        user = User(
            name="Concurrent Farmer",
            email="concurrent@example.com",
            password_hash="not-used-by-this-test",
        )
        db.add(user)
        db.flush()
        db.add(
            RefreshToken(
                user_id=user.id,
                token_hash=hash_refresh_token(raw_token),
                expires_at=datetime.now(timezone.utc) + timedelta(days=1),
            )
        )
        db.commit()

    barrier = Barrier(2)

    def revoke() -> None:
        barrier.wait()
        with factory() as db:
            revoke_refresh_token(db, raw_token)

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(revoke) for _ in range(2)]
        for future in futures:
            future.result()

    with factory() as db:
        tokens = db.scalars(select(RefreshToken)).all()
        assert len(tokens) == 1
        assert tokens[0].revoked_at is not None
    engine.dispose()


def test_database_failure_rolls_back_and_is_safely_wrapped() -> None:
    db = MagicMock(spec=Session)
    db.scalar.side_effect = SQLAlchemyError("database unavailable")

    with pytest.raises(RefreshTokenServiceError):
        revoke_refresh_token(db, generate_refresh_token())

    db.rollback.assert_called_once_with()
    db.commit.assert_not_called()


def test_unexpected_logout_failure_returns_safe_500(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail_logout(db: Session, raw_token: str) -> None:
        raise RefreshTokenServiceError

    monkeypatch.setattr(auth, "revoke_refresh_token", fail_logout)
    supplied_token = generate_refresh_token()
    response = logout(client, supplied_token)

    assert response.status_code == 500
    assert response.json() == {"detail": "Unable to log out at this time."}
    assert supplied_token not in response.text
    assert hash_refresh_token(supplied_token) not in response.text


def test_existing_access_jwt_remains_valid_after_logout(client: TestClient) -> None:
    registered, login = register_and_login(client)
    assert logout(client, login["refresh_token"]).status_code == 204

    response = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {login['access_token']}"},
    )

    assert response.status_code == 200
    assert response.json() == registered


def test_openapi_documents_json_logout_without_access_token_authentication(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/api/v1/auth/logout"]["post"]

    assert "application/json" in operation["requestBody"]["content"]
    assert "security" not in operation
    assert set(operation["responses"]) == {"204", "422"}
    assert "stateless access JWTs remain valid" in operation["description"]


def test_registration_login_refresh_profile_and_health_still_work(
    client: TestClient,
) -> None:
    root = client.get("/")
    health = client.get("/api/v1/health")
    registered, login = register_and_login(client)
    profile = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {login['access_token']}"},
    )
    refreshed = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": login["refresh_token"]},
    )

    assert root.status_code == 200
    assert health.status_code == 200
    assert profile.status_code == 200
    assert profile.json() == registered
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != login["refresh_token"]


def test_unknown_logout_does_not_change_token_count(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    register_and_login(client)
    with test_session_factory() as db:
        before = db.scalar(select(func.count()).select_from(RefreshToken))

    assert logout(client, generate_refresh_token()).status_code == 204
    with test_session_factory() as db:
        after = db.scalar(select(func.count()).select_from(RefreshToken))
    assert after == before
