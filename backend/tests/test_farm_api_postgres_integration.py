import os
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from app.db.models import Farm, RefreshToken, User
from app.db.session import SessionLocal
from app.main import app


pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_POSTGRES_INTEGRATION") != "1",
    reason="Set RUN_POSTGRES_INTEGRATION=1 for disposable PostgreSQL API tests.",
)

PASSWORD = "DisposableStep21Password!"


def _register_and_login(
    client: TestClient,
    email: str,
    name: str,
) -> tuple[dict[str, object], str]:
    registered = client.post(
        "/api/v1/auth/register",
        json={"name": name, "email": email, "password": PASSWORD},
    )
    assert registered.status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": PASSWORD},
    )
    assert login.status_code == 200
    return registered.json(), login.json()["access_token"]


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_real_postgres_two_user_farm_api_isolation_and_cleanup() -> None:
    suffix = uuid4().hex
    email_a = f"step21-a-{suffix}@example.com"
    email_b = f"step21-b-{suffix}@example.com"

    with SessionLocal() as db:
        users_before = db.scalar(select(func.count()).select_from(User))
        tokens_before = db.scalar(select(func.count()).select_from(RefreshToken))
        farms_before = db.scalar(select(func.count()).select_from(Farm))

    try:
        with TestClient(app) as client:
            user_a, token_a = _register_and_login(
                client, email_a, "Disposable Step 21 Farmer A"
            )
            created_a_response = client.post(
                "/api/v1/farms",
                headers=_auth(token_a),
                json={
                    "name": "Green Valley Farm",
                    "latitude": 6.927079,
                    "longitude": 79.861244,
                    "area_value": 2.5,
                    "area_unit": "acres",
                    "notes": "Disposable Step 21 API record",
                },
            )
            assert created_a_response.status_code == 201
            farm_a = created_a_response.json()
            assert farm_a["user_id"] == user_a["id"]

            with SessionLocal() as db:
                persisted_a = db.get(Farm, farm_a["id"])
                assert persisted_a is not None
                assert persisted_a.user_id == user_a["id"]

            read_a = client.get(
                f"/api/v1/farms/{farm_a['id']}", headers=_auth(token_a)
            )
            assert read_a.status_code == 200
            updated_a_response = client.put(
                f"/api/v1/farms/{farm_a['id']}",
                headers=_auth(token_a),
                json={
                    "name": "Green Valley Farm Updated",
                    "area_value": 3.75,
                    "area_unit": "acres",
                },
            )
            assert updated_a_response.status_code == 200
            updated_a = updated_a_response.json()
            assert updated_a["name"] == "Green Valley Farm Updated"
            assert updated_a["latitude"] is None
            assert updated_a["longitude"] is None

            user_b, token_b = _register_and_login(
                client, email_b, "Disposable Step 21 Farmer B"
            )
            created_b_response = client.post(
                "/api/v1/farms",
                headers=_auth(token_b),
                json={"name": "Hill Farm"},
            )
            assert created_b_response.status_code == 201
            farm_b = created_b_response.json()
            assert farm_b["user_id"] == user_b["id"]
            assert [farm["id"] for farm in client.get(
                "/api/v1/farms", headers=_auth(token_b)
            ).json()] == [farm_b["id"]]

            for method, payload in (
                ("get", None),
                ("put", {"name": "Unauthorized replacement"}),
                ("delete", None),
            ):
                rejected = client.request(
                    method,
                    f"/api/v1/farms/{farm_a['id']}",
                    headers=_auth(token_b),
                    json=payload,
                )
                assert rejected.status_code == 404
                assert rejected.json() == {"detail": "Farm not found."}

            unchanged_a = client.get(
                f"/api/v1/farms/{farm_a['id']}", headers=_auth(token_a)
            )
            assert unchanged_a.status_code == 200
            assert unchanged_a.json() == updated_a
            assert [farm["id"] for farm in client.get(
                "/api/v1/farms", headers=_auth(token_a)
            ).json()] == [farm_a["id"]]

            assert client.get("/api/v1/farms").status_code == 401
            assert client.get(
                "/api/v1/farms", headers=_auth("invalid-token")
            ).status_code == 401
            assert client.post(
                "/api/v1/farms",
                headers=_auth(token_a),
                json={"name": "Invalid Latitude", "latitude": 90.000001},
            ).status_code == 422
            assert client.post(
                "/api/v1/farms",
                headers=_auth(token_a),
                json={"name": "Invalid Area", "area_value": 0},
            ).status_code == 422

            assert client.get(
                "/api/v1/auth/me", headers=_auth(token_a)
            ).json()["id"] == user_a["id"]
            assert client.get(
                "/api/v1/auth/me", headers=_auth(token_b)
            ).json()["id"] == user_b["id"]

            deleted_a = client.delete(
                f"/api/v1/farms/{farm_a['id']}", headers=_auth(token_a)
            )
            assert deleted_a.status_code == 204
            assert deleted_a.content == b""

            with SessionLocal() as db:
                assert db.get(Farm, farm_a["id"]) is None
                persisted_b = db.get(Farm, farm_b["id"])
                assert persisted_b is not None
                assert persisted_b.name == "Hill Farm"
    finally:
        with SessionLocal() as db:
            disposable_users = list(
                db.scalars(select(User).where(User.email.in_([email_a, email_b])))
            )
            for user in disposable_users:
                db.delete(user)
            db.commit()

            assert db.scalar(select(func.count()).select_from(User)) == users_before
            assert (
                db.scalar(select(func.count()).select_from(RefreshToken))
                == tokens_before
            )
            assert db.scalar(select(func.count()).select_from(Farm)) == farms_before
