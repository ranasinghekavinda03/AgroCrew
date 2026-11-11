from datetime import datetime, timedelta, timezone
import time

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.core.security import create_access_token
from app.db.models import CropCycle, Farm, User


PASSWORD = "StrongTestPassword123!"


def _login(client: TestClient, email: str) -> str:
    response = client.post("/api/v1/auth/register", json={"name": "Farmer", "email": email, "password": PASSWORD})
    assert response.status_code == 201
    response = client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD})
    assert response.status_code == 200
    return response.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _farm(client: TestClient, token: str, name: str = "Farm") -> dict:
    response = client.post("/api/v1/farms", headers=_headers(token), json={"name": name})
    assert response.status_code == 201
    return response.json()


def _crop(client: TestClient, token: str, farm_id: int, **extra: object):
    payload = {"farm_id": farm_id, "crop_type": "Tomato", "planting_date": "2026-10-15", **extra}
    return client.post("/api/v1/crops", headers=_headers(token), json=payload)


def test_create_validates_and_persists_crop_cycle(client: TestClient, test_session_factory: sessionmaker[Session]) -> None:
    token = _login(client, "crop-create@example.com")
    farm = _farm(client, token)
    response = _crop(client, token, farm["id"], crop_type="  Tōmato  ", variety=" Roma ", expected_harvest_date="2026-12-20", plant_count=120, notes="North field")
    assert response.status_code == 201
    body = response.json()
    assert body["id"] > 0 and body["farm_id"] == farm["id"]
    assert body["crop_type"] == "Tōmato" and body["variety"] == "Roma"
    assert body["status"] == "planned" and body["plant_count"] == 120
    assert body["planting_date"] == "2026-10-15" and body["expected_harvest_date"] == "2026-12-20"
    assert "user_id" not in body and "password_hash" not in body
    with test_session_factory() as db:
        persisted = db.get(CropCycle, body["id"])
        assert persisted and persisted.farm_id == farm["id"] and persisted.plant_count == 120


@pytest.mark.parametrize("payload", [
    {"crop_type": "   "}, {"crop_type": "x" * 129}, {"planting_date": "2026-02-30"},
    {"planting_date": "2026-10-15T00:00:00Z"}, {"expected_harvest_date": "2026-10-14"},
    {"status": "growing"}, {"plant_count": 0}, {"plant_count": -1}, {"plant_count": True},
    {"user_id": 44}, {"created_at": "2026-10-15T00:00:00Z"}, {"notes": "x" * 10001},
])
def test_invalid_create_payloads_do_not_persist(client: TestClient, test_session_factory: sessionmaker[Session], payload: dict) -> None:
    token = _login(client, "crop-invalid@example.com")
    farm = _farm(client, token)
    response = _crop(client, token, farm["id"], **payload)
    assert response.status_code == 422
    with test_session_factory() as db:
        assert list(db.scalars(select(CropCycle))) == []


def test_create_hides_missing_and_foreign_farms(client: TestClient) -> None:
    owner = _login(client, "crop-owner@example.com")
    other = _login(client, "crop-other@example.com")
    farm = _farm(client, owner)
    foreign = _crop(client, other, farm["id"])
    missing = _crop(client, other, 999999)
    assert foreign.status_code == missing.status_code == 404
    assert foreign.json() == missing.json() == {"detail": "Farm not found."}


def test_list_filter_pagination_and_owner_isolation(client: TestClient) -> None:
    token_a = _login(client, "crop-list-a@example.com")
    token_b = _login(client, "crop-list-b@example.com")
    farm_a = _farm(client, token_a)
    farm_a2 = _farm(client, token_a, "Farm 2")
    farm_b = _farm(client, token_b)
    assert client.get("/api/v1/crops", headers=_headers(token_a)).json() == []
    ids = [_crop(client, token_a, farm_a["id"], status="active").json()["id"], _crop(client, token_a, farm_a2["id"]).json()["id"]]
    other_id = _crop(client, token_b, farm_b["id"]).json()["id"]
    listed = client.get("/api/v1/crops?limit=1", headers=_headers(token_a))
    assert listed.status_code == 200 and [c["id"] for c in listed.json()] == ids[:1]
    assert [c["id"] for c in client.get("/api/v1/crops?offset=1", headers=_headers(token_a)).json()] == ids[1:]
    assert [c["id"] for c in client.get(f"/api/v1/crops?farm_id={farm_a2['id']}", headers=_headers(token_a)).json()] == ids[1:]
    assert all(c["id"] != other_id for c in client.get("/api/v1/crops", headers=_headers(token_a)).json())
    assert client.get(f"/api/v1/crops?farm_id={farm_b['id']}", headers=_headers(token_a)).json() == {"detail": "Farm not found."}
    assert client.get("/api/v1/crops?farm_id=999999", headers=_headers(token_a)).status_code == 404
    for query in ("limit=0", "limit=101", "offset=-1", "farm_id=0"):
        assert client.get(f"/api/v1/crops?{query}", headers=_headers(token_a)).status_code == 422


def test_get_put_delete_ownership_and_full_replacement(client: TestClient, test_session_factory: sessionmaker[Session]) -> None:
    token_a = _login(client, "crop-crud-a@example.com")
    token_b = _login(client, "crop-crud-b@example.com")
    farm = _farm(client, token_a)
    crop = _crop(client, token_a, farm["id"], variety="Roma", plant_count=10, notes="Clear me").json()
    assert client.get(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a)).status_code == 200
    foreign = client.get(f"/api/v1/crops/{crop['id']}", headers=_headers(token_b))
    missing = client.get("/api/v1/crops/999999", headers=_headers(token_a))
    assert foreign.status_code == missing.status_code == 404 and foreign.json() == missing.json()
    time.sleep(1.05)
    updated_response = client.put(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a), json={"crop_type": "Tomato", "planting_date": "2026-10-16", "status": "active"})
    assert updated_response.status_code == 200
    updated = updated_response.json()
    assert updated["id"] == crop["id"] and updated["farm_id"] == farm["id"]
    assert updated["created_at"] == crop["created_at"] and updated["updated_at"] > crop["updated_at"]
    assert updated["variety"] is None and updated["plant_count"] is None and updated["notes"] is None
    assert client.put(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a), json={"crop_type": "Moved", "planting_date": "2026-10-16", "status": "active", "farm_id": 2}).status_code == 422
    assert client.put(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a), json={"crop_type": "Bad", "planting_date": "2026-10-16", "expected_harvest_date": "2026-01-01", "status": "active"}).status_code == 422
    assert client.put(f"/api/v1/crops/{crop['id']}", headers=_headers(token_b), json={"crop_type": "Stolen", "planting_date": "2026-10-16", "status": "active"}).status_code == 404
    assert client.delete(f"/api/v1/crops/{crop['id']}", headers=_headers(token_b)).status_code == 404
    deleted = client.delete(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a))
    assert deleted.status_code == 204 and deleted.content == b""
    assert client.get(f"/api/v1/crops/{crop['id']}", headers=_headers(token_a)).status_code == 404
    assert client.get(f"/api/v1/farms/{farm['id']}", headers=_headers(token_a)).status_code == 200
    with test_session_factory() as db:
        assert db.get(CropCycle, crop["id"]) is None
        assert db.get(Farm, farm["id"]) is not None


@pytest.mark.parametrize("method,path,body", [
    ("post", "/api/v1/crops", {"farm_id": 1, "crop_type": "A", "planting_date": "2026-01-01"}),
    ("get", "/api/v1/crops", None), ("get", "/api/v1/crops/1", None),
    ("put", "/api/v1/crops/1", {"crop_type": "A", "planting_date": "2026-01-01", "status": "planned"}),
    ("delete", "/api/v1/crops/1", None),
])
def test_all_crop_routes_require_bearer_auth(client: TestClient, method: str, path: str, body: dict | None) -> None:
    response = client.request(method, path, json=body)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_crop_auth_rejects_malformed_expired_invalid_signature_inactive_and_deleted(client: TestClient, test_session_factory: sessionmaker[Session]) -> None:
    token = _login(client, "crop-auth@example.com")
    malformed = "not-a-jwt"
    expired = create_access_token(1, now=datetime.now(timezone.utc) - timedelta(minutes=31))
    bad_signature = create_access_token(1)[:-2] + "xx"
    with test_session_factory() as db:
        user = db.scalar(select(User).where(User.email == "crop-auth@example.com"))
        assert user
        inactive_id = user.id
        user.is_active = False
        db.commit()
    inactive = create_access_token(inactive_id)
    response = client.get("/api/v1/crops", headers=_headers(inactive))
    assert response.status_code == 401 and response.headers["www-authenticate"] == "Bearer"
    with test_session_factory() as db:
        user = db.get(User, inactive_id)
        assert user
        user.is_active = True
        db.commit()
        db.delete(user)
        db.commit()
    deleted = create_access_token(inactive_id)
    for candidate in (malformed, expired, bad_signature, deleted):
        response = client.get("/api/v1/crops", headers=_headers(candidate))
        assert response.status_code == 401 and response.headers["www-authenticate"] == "Bearer"


def test_crop_openapi_documents_secure_crud_and_safe_response(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()
    paths = schema["paths"]
    assert set(paths["/api/v1/crops"]) >= {"post", "get"}
    assert set(paths["/api/v1/crops/{crop_cycle_id}"]) >= {"get", "put", "delete"}
    for path, method in (("/api/v1/crops", "post"), ("/api/v1/crops", "get"), ("/api/v1/crops/{crop_cycle_id}", "get"), ("/api/v1/crops/{crop_cycle_id}", "put"), ("/api/v1/crops/{crop_cycle_id}", "delete")):
        operation = paths[path][method]
        assert operation["security"] == [{"HTTPBearer": []}]
        assert {"401", "422"}.issubset(operation["responses"])
    assert "409" in paths["/api/v1/crops/{crop_cycle_id}"]["delete"]["responses"]
    assert "farm_id" not in schema["components"]["schemas"]["CropCycleUpdate"]["properties"]
    assert "password_hash" not in str(schema["components"]["schemas"]["CropCycleResponse"])
