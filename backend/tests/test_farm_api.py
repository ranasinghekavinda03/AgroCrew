from datetime import datetime, timedelta, timezone
from decimal import Decimal
import time

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.core.security import create_access_token
from app.db.models import Farm, User


PASSWORD = "StrongTestPassword123!"


def register_and_login(
    client: TestClient,
    email: str,
    name: str = "Test Farmer",
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


def authorization(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def create_farm(
    client: TestClient,
    token: str,
    **overrides: object,
):
    payload: dict[str, object] = {"name": "Green Valley Farm"}
    payload.update(overrides)
    return client.post(
        "/api/v1/farms",
        headers=authorization(token),
        json=payload,
    )


def test_authenticated_user_creates_persisted_farm_with_correct_owner(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    user, token = register_and_login(client, "farm-create@example.com")
    response = create_farm(
        client,
        token,
        name="  Green Valley Farm  ",
        latitude=6.927079,
        longitude=79.861244,
        area_value=2.5,
        area_unit="  acres  ",
        notes="Main vegetable cultivation area",
    )

    assert response.status_code == 201
    body = response.json()
    assert body["id"] > 0
    assert body["user_id"] == user["id"]
    assert body["name"] == "Green Valley Farm"
    assert body["latitude"] == 6.927079
    assert body["longitude"] == 79.861244
    assert body["area_value"] == 2.5
    assert body["area_unit"] == "acres"
    assert set(body) == {
        "id",
        "user_id",
        "name",
        "latitude",
        "longitude",
        "area_value",
        "area_unit",
        "notes",
        "created_at",
        "updated_at",
    }

    with test_session_factory() as db:
        farm = db.get(Farm, body["id"])
        assert farm is not None
        assert farm.user_id == user["id"]
        assert farm.area_value == Decimal("2.5000")


def test_create_accepts_all_optional_fields_as_omitted_or_null(
    client: TestClient,
) -> None:
    _, token = register_and_login(client, "farm-optional@example.com")
    omitted = create_farm(client, token)
    explicit_null = create_farm(
        client,
        token,
        name="Null Fields Farm",
        latitude=None,
        longitude=None,
        area_value=None,
        area_unit=None,
        notes=None,
    )

    assert omitted.status_code == 201
    assert explicit_null.status_code == 201
    for body in (omitted.json(), explicit_null.json()):
        assert body["latitude"] is None
        assert body["longitude"] is None
        assert body["area_value"] is None
        assert body["area_unit"] is None
        assert body["notes"] is None


@pytest.mark.parametrize(
    "payload",
    [
        {"name": ""},
        {"name": "   "},
        {"name": "x" * 256},
        {"name": "Farm", "latitude": 90.000001},
        {"name": "Farm", "latitude": -90.000001},
        {"name": "Farm", "longitude": 180.000001},
        {"name": "Farm", "longitude": -180.000001},
        {"name": "Farm", "area_value": 0},
        {"name": "Farm", "area_value": -1},
        {"name": "Farm", "area_value": "NaN"},
        {"name": "Farm", "area_value": "Infinity"},
        {"name": "Farm", "area_value": "10000000000.0000"},
        {"name": "Farm", "area_value": "1.00001"},
        {"name": "Farm", "area_unit": "   "},
        {"name": "Farm", "area_unit": "x" * 33},
        {"name": "Farm", "notes": "x" * 10_001},
        {"name": "Farm", "user_id": 999},
    ],
)
def test_create_rejects_invalid_or_ownership_input_without_partial_record(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
    payload: dict[str, object],
) -> None:
    _, token = register_and_login(client, "farm-invalid@example.com")

    response = client.post(
        "/api/v1/farms",
        headers=authorization(token),
        json=payload,
    )

    assert response.status_code == 422
    with test_session_factory() as db:
        assert list(db.scalars(select(Farm))) == []


@pytest.mark.parametrize(
    ("method", "path", "json"),
    [
        ("post", "/api/v1/farms", {"name": "Farm"}),
        ("get", "/api/v1/farms", None),
        ("get", "/api/v1/farms/1", None),
        ("put", "/api/v1/farms/1", {"name": "Farm"}),
        ("delete", "/api/v1/farms/1", None),
    ],
)
def test_all_farm_routes_require_bearer_authentication(
    client: TestClient,
    method: str,
    path: str,
    json: dict[str, object] | None,
) -> None:
    response = client.request(method, path, json=json)
    assert response.status_code == 401
    assert response.json() == {"detail": "Could not validate credentials."}
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("token", ["not-a-jwt"])
def test_invalid_access_token_returns_401(client: TestClient, token: str) -> None:
    response = client.get("/api/v1/farms", headers=authorization(token))
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_expired_access_token_returns_401(client: TestClient) -> None:
    user, _ = register_and_login(client, "farm-expired@example.com")
    token = create_access_token(
        user["id"],
        now=datetime.now(timezone.utc) - timedelta(minutes=31),
    )
    response = client.get("/api/v1/farms", headers=authorization(token))
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_list_is_empty_then_owner_scoped_stably_paginated(client: TestClient) -> None:
    _, token_a = register_and_login(client, "farm-list-a@example.com", "Farmer A")
    _, token_b = register_and_login(client, "farm-list-b@example.com", "Farmer B")
    assert client.get("/api/v1/farms", headers=authorization(token_a)).json() == []

    ids_a = [
        create_farm(client, token_a, name=f"Farm {index}").json()["id"]
        for index in range(3)
    ]
    farm_b = create_farm(client, token_b, name="Other Owner Farm").json()

    first_page = client.get(
        "/api/v1/farms?limit=2&offset=0", headers=authorization(token_a)
    )
    second_page = client.get(
        "/api/v1/farms?limit=2&offset=2", headers=authorization(token_a)
    )
    list_b = client.get("/api/v1/farms", headers=authorization(token_b))

    assert first_page.status_code == 200
    assert [farm["id"] for farm in first_page.json()] == ids_a[:2]
    assert [farm["id"] for farm in second_page.json()] == ids_a[2:]
    assert [farm["id"] for farm in list_b.json()] == [farm_b["id"]]
    assert farm_b["id"] not in ids_a


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1"])
def test_list_rejects_unbounded_or_invalid_pagination(
    client: TestClient,
    query: str,
) -> None:
    _, token = register_and_login(client, "farm-page-invalid@example.com")
    response = client.get(
        f"/api/v1/farms?{query}", headers=authorization(token)
    )
    assert response.status_code == 422


def test_get_returns_own_farm_and_hides_other_or_missing_farms(
    client: TestClient,
) -> None:
    _, token_a = register_and_login(client, "farm-read-a@example.com")
    _, token_b = register_and_login(client, "farm-read-b@example.com")
    farm = create_farm(client, token_a).json()

    own = client.get(
        f"/api/v1/farms/{farm['id']}", headers=authorization(token_a)
    )
    other = client.get(
        f"/api/v1/farms/{farm['id']}", headers=authorization(token_b)
    )
    missing = client.get("/api/v1/farms/999999", headers=authorization(token_a))

    assert own.status_code == 200
    assert own.json() == farm
    assert other.status_code == 404
    assert missing.status_code == 404
    assert other.json() == missing.json() == {"detail": "Farm not found."}


def test_put_replaces_fields_preserves_identity_and_timestamps(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    user, token = register_and_login(client, "farm-update@example.com")
    created = create_farm(
        client,
        token,
        latitude=1,
        longitude=2,
        area_value=3,
        area_unit="hectares",
        notes="Clear me",
    ).json()
    time.sleep(1.05)

    response = client.put(
        f"/api/v1/farms/{created['id']}",
        headers=authorization(token),
        json={"name": " Replacement Farm "},
    )

    assert response.status_code == 200
    updated = response.json()
    assert updated["id"] == created["id"]
    assert updated["user_id"] == user["id"] == created["user_id"]
    assert updated["created_at"] == created["created_at"]
    assert updated["updated_at"] > created["updated_at"]
    assert updated["name"] == "Replacement Farm"
    for field in ("latitude", "longitude", "area_value", "area_unit", "notes"):
        assert updated[field] is None

    with test_session_factory() as db:
        farm = db.get(Farm, created["id"])
        assert farm is not None
        assert farm.name == "Replacement Farm"
        assert farm.notes is None


def test_put_rejects_owner_change_invalid_data_and_other_owner(
    client: TestClient,
) -> None:
    _, token_a = register_and_login(client, "farm-put-a@example.com")
    _, token_b = register_and_login(client, "farm-put-b@example.com")
    farm = create_farm(client, token_a).json()

    injected = client.put(
        f"/api/v1/farms/{farm['id']}",
        headers=authorization(token_a),
        json={"name": "Changed", "user_id": 999},
    )
    invalid = client.put(
        f"/api/v1/farms/{farm['id']}",
        headers=authorization(token_a),
        json={"name": "Changed", "latitude": 91},
    )
    other = client.put(
        f"/api/v1/farms/{farm['id']}",
        headers=authorization(token_b),
        json={"name": "Stolen"},
    )
    missing = client.put(
        "/api/v1/farms/999999",
        headers=authorization(token_a),
        json={"name": "Missing"},
    )

    assert injected.status_code == 422
    assert invalid.status_code == 422
    assert other.status_code == 404
    assert missing.status_code == 404
    unchanged = client.get(
        f"/api/v1/farms/{farm['id']}", headers=authorization(token_a)
    ).json()
    assert unchanged["name"] == "Green Valley Farm"
    assert unchanged["user_id"] == farm["user_id"]


def test_delete_removes_only_owned_farm_and_keeps_owner_and_other_farms(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    user_a, token_a = register_and_login(client, "farm-delete-a@example.com")
    _, token_b = register_and_login(client, "farm-delete-b@example.com")
    deleted_farm = create_farm(client, token_a, name="Delete Me").json()
    kept_farm = create_farm(client, token_a, name="Keep Me").json()

    forbidden = client.delete(
        f"/api/v1/farms/{deleted_farm['id']}", headers=authorization(token_b)
    )
    success = client.delete(
        f"/api/v1/farms/{deleted_farm['id']}", headers=authorization(token_a)
    )
    missing = client.delete(
        f"/api/v1/farms/{deleted_farm['id']}", headers=authorization(token_a)
    )

    assert forbidden.status_code == 404
    assert success.status_code == 204
    assert success.content == b""
    assert missing.status_code == 404
    assert [farm["id"] for farm in client.get(
        "/api/v1/farms", headers=authorization(token_a)
    ).json()] == [kept_farm["id"]]
    with test_session_factory() as db:
        assert db.get(User, user_a["id"]) is not None
        assert db.get(Farm, deleted_farm["id"]) is None
        assert db.get(Farm, kept_farm["id"]) is not None


def test_openapi_documents_five_bearer_secured_farm_operations(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    paths = schema["paths"]
    assert set(paths["/api/v1/farms"]) >= {"post", "get"}
    assert set(paths["/api/v1/farms/{farm_id}"]) >= {"get", "put", "delete"}
    for path, method in (
        ("/api/v1/farms", "post"),
        ("/api/v1/farms", "get"),
        ("/api/v1/farms/{farm_id}", "get"),
        ("/api/v1/farms/{farm_id}", "put"),
        ("/api/v1/farms/{farm_id}", "delete"),
    ):
        operation = paths[path][method]
        assert operation["security"] == [{"HTTPBearer": []}]
        assert "401" in operation["responses"]

