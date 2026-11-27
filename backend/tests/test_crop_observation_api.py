from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import CropCycle, CropObservation, Farm
from app.services.crop_observation_service import CropObservationServiceError


PASSWORD = "StrongTestPassword123!"


def _login(client: TestClient, email: str) -> str:
    registered = client.post(
        "/api/v1/auth/register",
        json={"name": "Observation Farmer", "email": email, "password": PASSWORD},
    )
    assert registered.status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": PASSWORD},
    )
    assert login.status_code == 200
    return login.json()["access_token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _crop(client: TestClient, token: str, suffix: str = "") -> dict:
    farm = client.post(
        "/api/v1/farms",
        headers=_headers(token),
        json={"name": f"Observation Farm {suffix}"},
    )
    assert farm.status_code == 201
    crop = client.post(
        "/api/v1/crops",
        headers=_headers(token),
        json={
            "farm_id": farm.json()["id"],
            "crop_type": f"Tomato {suffix}".strip(),
            "planting_date": "2026-11-01",
        },
    )
    assert crop.status_code == 201
    return crop.json()


def _post(client: TestClient, token: str, crop_id: int, **overrides: object):
    payload = {
        "observation_date": "2026-11-27",
        "category": "growth",
        "notes": "  New leaves appeared 🌱  ",
        **overrides,
    }
    return client.post(
        f"/api/v1/crops/{crop_id}/observations",
        headers=_headers(token),
        json=payload,
    )


def test_post_list_and_detail_contract(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    token = _login(client, "observation-contract@example.com")
    crop = _crop(client, token)
    response = _post(client, token, crop["id"])
    assert response.status_code == 201
    body = response.json()
    assert set(body) == {
        "id", "crop_cycle_id", "observation_date", "category", "notes",
        "created_at", "updated_at",
    }
    assert body["id"] > 0
    assert body["crop_cycle_id"] == crop["id"]
    assert body["observation_date"] == "2026-11-27"
    assert body["category"] == "growth"
    assert body["notes"] == "New leaves appeared 🌱"
    assert isinstance(body["created_at"], str)
    assert isinstance(body["updated_at"], str)

    listed = client.get(
        f"/api/v1/crops/{crop['id']}/observations",
        headers=_headers(token),
    )
    assert listed.status_code == 200
    assert listed.json() == [body]
    detail = client.get(
        f"/api/v1/crops/{crop['id']}/observations/{body['id']}",
        headers=_headers(token),
    )
    assert detail.status_code == 200
    assert detail.json() == body

    with test_session_factory() as db:
        persisted = db.get(CropObservation, body["id"])
        assert persisted is not None and persisted.notes == "New leaves appeared 🌱"


def test_empty_list_and_out_of_range_offset(client: TestClient) -> None:
    token = _login(client, "observation-empty@example.com")
    crop = _crop(client, token)
    base = f"/api/v1/crops/{crop['id']}/observations"
    assert client.get(base, headers=_headers(token)).json() == []
    _post(client, token, crop["id"])
    response = client.get(f"{base}?offset=999", headers=_headers(token))
    assert response.status_code == 200 and response.json() == []


def test_owner_isolation_missing_parent_and_wrong_parent(client: TestClient) -> None:
    owner = _login(client, "observation-owner@example.com")
    other = _login(client, "observation-other@example.com")
    crop = _crop(client, owner, "Owner")
    other_crop = _crop(client, other, "Other")
    observation = _post(client, owner, crop["id"]).json()

    foreign_create = _post(client, other, crop["id"])
    missing_create = _post(client, other, 999_999)
    assert foreign_create.status_code == missing_create.status_code == 404
    assert foreign_create.json() == missing_create.json() == {"detail": "Crop not found."}
    foreign_list = client.get(
        f"/api/v1/crops/{crop['id']}/observations", headers=_headers(other)
    )
    missing_list = client.get(
        "/api/v1/crops/999999/observations", headers=_headers(other)
    )
    assert foreign_list.status_code == missing_list.status_code == 404
    assert foreign_list.json() == missing_list.json() == {"detail": "Crop not found."}

    paths = [
        f"/api/v1/crops/{crop['id']}/observations/{observation['id']}",
        f"/api/v1/crops/{other_crop['id']}/observations/{observation['id']}",
        f"/api/v1/crops/{crop['id']}/observations/999999",
    ]
    responses = [client.get(path, headers=_headers(other)) for path in paths]
    assert all(item.status_code == 404 for item in responses)
    assert all(item.json() == {"detail": "Observation not found."} for item in responses)
    assert client.get(
        f"/api/v1/crops/{other_crop['id']}/observations",
        headers=_headers(other),
    ).json() == []


@pytest.mark.parametrize(
    "overrides",
    [
        {"category": "disease"},
        {"category": "GENERAL"},
        {"observation_date": "2026-02-30"},
        {"observation_date": "2026-11-27T00:00:00Z"},
        {"notes": "   "},
        {"notes": "x" * 10_001},
        {"crop_cycle_id": 1},
        {"farm_id": 1},
        {"user_id": 1},
        {"id": 1},
        {"created_at": "2026-11-27T00:00:00Z"},
    ],
)
def test_invalid_post_payloads_return_422_and_do_not_persist(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
    overrides: dict[str, object],
) -> None:
    token = _login(client, f"invalid-{next(iter(overrides))}-{len(str(overrides))}@example.com")
    crop = _crop(client, token)
    response = _post(client, token, crop["id"], **overrides)
    assert response.status_code == 422
    assert all("input" not in error for error in response.json()["detail"])
    with test_session_factory() as db:
        assert list(db.scalars(select(CropObservation))) == []


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/crops/0/observations",
        "/api/v1/crops/-1/observations",
        "/api/v1/crops/1/observations/0",
        "/api/v1/crops/1/observations/-1",
        "/api/v1/crops/1/observations?limit=0",
        "/api/v1/crops/1/observations?limit=101",
        "/api/v1/crops/1/observations?offset=-1",
    ],
)
def test_positive_ids_and_pagination_bounds_return_422(
    client: TestClient,
    path: str,
) -> None:
    token = _login(client, f"bounds-{abs(hash(path))}@example.com")
    assert client.get(path, headers=_headers(token)).status_code == 422


def test_list_order_and_boundary_pagination(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    token = _login(client, "observation-pagination@example.com")
    crop = _crop(client, token)
    with test_session_factory() as db:
        stamp = db.scalar(select(CropCycle.created_at).where(CropCycle.id == crop["id"]))
        assert stamp is not None
        rows = [
            CropObservation(crop_cycle_id=crop["id"], observation_date=date(2026, 11, 26), category="general", notes="older", created_at=stamp, updated_at=stamp),
            CropObservation(crop_cycle_id=crop["id"], observation_date=date(2026, 11, 27), category="general", notes="same-1", created_at=stamp, updated_at=stamp),
            CropObservation(crop_cycle_id=crop["id"], observation_date=date(2026, 11, 27), category="general", notes="same-2", created_at=stamp, updated_at=stamp),
        ]
        db.add_all(rows)
        db.commit()
    base = f"/api/v1/crops/{crop['id']}/observations"
    first = client.get(f"{base}?limit=2&offset=0", headers=_headers(token))
    second = client.get(f"{base}?limit=1&offset=2", headers=_headers(token))
    assert [item["notes"] for item in first.json()] == ["same-2", "same-1"]
    assert [item["notes"] for item in second.json()] == ["older"]
    assert client.get(f"{base}?limit=100&offset=0", headers=_headers(token)).status_code == 200


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("post", "/api/v1/crops/1/observations", {"observation_date": "2026-11-27", "category": "general", "notes": "Note"}),
        ("get", "/api/v1/crops/1/observations", None),
        ("get", "/api/v1/crops/1/observations/1", None),
    ],
)
def test_all_observation_routes_require_bearer_auth(
    client: TestClient, method: str, path: str, body: dict | None
) -> None:
    response = client.request(method, path, json=body)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_observed_crop_delete_conflicts_and_childless_crop_deletes(
    client: TestClient,
    test_session_factory: sessionmaker[Session],
) -> None:
    token = _login(client, "observation-delete@example.com")
    childless = _crop(client, token, "Childless")
    assert client.delete(
        f"/api/v1/crops/{childless['id']}", headers=_headers(token)
    ).status_code == 204

    protected = _crop(client, token, "Protected")
    observation = _post(client, token, protected["id"]).json()
    rejected = client.delete(
        f"/api/v1/crops/{protected['id']}", headers=_headers(token)
    )
    assert rejected.status_code == 409
    assert rejected.json() == {
        "detail": "Crop cannot be deleted while related records exist."
    }
    with test_session_factory() as db:
        assert db.get(CropCycle, protected["id"]) is not None
        assert db.get(CropObservation, observation["id"]) is not None
        farm_id = protected["farm_id"]
    assert client.delete(f"/api/v1/farms/{farm_id}", headers=_headers(token)).status_code == 409


def test_route_sanitizes_service_failure(
    client: TestClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    token = _login(client, "observation-error@example.com")
    crop = _crop(client, token)

    def fail(*_args, **_kwargs):
        raise CropObservationServiceError("secret database details")

    monkeypatch.setattr(
        "app.api.v1.endpoints.crop_observations.create_crop_observation", fail
    )
    response = _post(client, token, crop["id"])
    assert response.status_code == 500
    assert response.json() == {
        "detail": "Unable to process the observation operation at this time."
    }
    assert "secret" not in response.text


def test_openapi_documents_nested_secure_read_create_contract(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()
    collection = schema["paths"]["/api/v1/crops/{crop_cycle_id}/observations"]
    detail = schema["paths"]["/api/v1/crops/{crop_cycle_id}/observations/{observation_id}"]
    assert set(collection) >= {"post", "get"}
    assert set(detail) >= {"get"}
    assert "put" not in collection and "delete" not in collection
    assert "put" not in detail and "delete" not in detail
    for operation in (collection["post"], collection["get"], detail["get"]):
        assert operation["security"] == [{"HTTPBearer": []}]
        assert {"401", "404", "422"}.issubset(operation["responses"])
    create_properties = schema["components"]["schemas"]["CropObservationCreate"]["properties"]
    assert set(create_properties) == {"observation_date", "category", "notes"}

