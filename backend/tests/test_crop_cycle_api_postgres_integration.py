"""Opt-in real PostgreSQL ownership and CropCycle CRUD verification."""
import os
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete, func, select

from app.db.models import CropCycle, Farm, RefreshToken, User
from app.db.session import SessionLocal, engine
from app.main import app


pytestmark = pytest.mark.skipif(os.environ.get("RUN_POSTGRES_INTEGRATION") != "1", reason="Set RUN_POSTGRES_INTEGRATION=1 for disposable PostgreSQL tests.")
PASSWORD = "DisposableStep26Password!"


def test_real_postgres_two_farmer_crop_cycle_crud_and_cleanup() -> None:
    assert engine.dialect.name == "postgresql"
    suffix = uuid4().hex
    emails = [f"step26-a-{suffix}@example.com", f"step26-b-{suffix}@example.com"]
    with SessionLocal() as db:
        before = {model: db.scalar(select(func.count()).select_from(model)) for model in (User, RefreshToken, Farm, CropCycle)}
    try:
        with TestClient(app) as client:
            def register(email: str, name: str) -> tuple[int, str]:
                response = client.post("/api/v1/auth/register", json={"name": name, "email": email, "password": PASSWORD})
                assert response.status_code == 201
                login = client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD})
                assert login.status_code == 200
                token = login.json()["access_token"]
                me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
                assert me.status_code == 200 and me.json()["email"] == email
                return response.json()["id"], token

            id_a, token_a = register(emails[0], "Disposable Step 26 A")
            id_b, token_b = register(emails[1], "Disposable Step 26 B")
            auth_a = {"Authorization": f"Bearer {token_a}"}
            auth_b = {"Authorization": f"Bearer {token_b}"}
            farm_a = client.post("/api/v1/farms", headers=auth_a, json={"name": "Green Valley Disposable"})
            farm_b = client.post("/api/v1/farms", headers=auth_b, json={"name": "Hill Disposable"})
            assert farm_a.status_code == farm_b.status_code == 201
            farm_a_id, farm_b_id = farm_a.json()["id"], farm_b.json()["id"]
            with SessionLocal() as db:
                assert db.get(Farm, farm_a_id).user_id == id_a  # type: ignore[union-attr]
                assert db.get(Farm, farm_b_id).user_id == id_b  # type: ignore[union-attr]

            created = client.post("/api/v1/crops", headers=auth_a, json={"farm_id": farm_a_id, "crop_type": "Tomato", "variety": "Roma", "planting_date": "2026-10-15", "expected_harvest_date": "2026-12-20", "status": "active", "plant_count": 120, "notes": "Disposable Step 26"})
            assert created.status_code == 201
            crop_id = created.json()["id"]
            with SessionLocal() as db:
                crop = db.get(CropCycle, crop_id)
                assert crop is not None and crop.farm_id == farm_a_id and crop.crop_type == "Tomato"
                assert str(crop.planting_date) == "2026-10-15" and str(crop.expected_harvest_date) == "2026-12-20"
                assert crop.status == "active" and crop.plant_count == 120
                created_at = crop.created_at

            assert [x["id"] for x in client.get("/api/v1/crops", headers=auth_a).json()] == [crop_id]
            assert [x["id"] for x in client.get(f"/api/v1/crops?farm_id={farm_a_id}", headers=auth_a).json()] == [crop_id]
            assert client.get(f"/api/v1/crops/{crop_id}", headers=auth_a).status_code == 200
            updated = client.put(f"/api/v1/crops/{crop_id}", headers=auth_a, json={"crop_type": "Tomato", "variety": "Roma Select", "planting_date": "2026-10-15", "expected_harvest_date": "2026-12-20", "status": "active", "plant_count": 120, "notes": "Updated disposable note"})
            assert updated.status_code == 200 and updated.json()["created_at"] == created.json()["created_at"]
            with SessionLocal() as db:
                saved = db.get(CropCycle, crop_id)
                assert saved and saved.farm_id == farm_a_id and saved.created_at == created_at
                assert saved.variety == "Roma Select" and saved.notes == "Updated disposable note"

            potato = client.post("/api/v1/crops", headers=auth_b, json={"farm_id": farm_b_id, "crop_type": "Potato", "planting_date": "2026-11-01"})
            assert potato.status_code == 201
            crop_b_id = potato.json()["id"]
            assert [x["id"] for x in client.get("/api/v1/crops", headers=auth_b).json()] == [crop_b_id]
            assert client.get(f"/api/v1/crops/{crop_id}", headers=auth_b).status_code == 404
            assert client.put(f"/api/v1/crops/{crop_id}", headers=auth_b, json={"crop_type": "Stolen", "planting_date": "2026-10-15", "status": "active"}).status_code == 404
            assert client.delete(f"/api/v1/crops/{crop_id}", headers=auth_b).status_code == 404
            assert client.post("/api/v1/crops", headers=auth_b, json={"farm_id": farm_a_id, "crop_type": "Nope", "planting_date": "2026-10-15"}).status_code == 404
            assert client.get(f"/api/v1/crops/{crop_id}", headers=auth_a).json()["variety"] == "Roma Select"

            protected = client.delete(f"/api/v1/farms/{farm_a_id}", headers=auth_a)
            assert protected.status_code == 409
            with SessionLocal() as db:
                assert db.get(Farm, farm_a_id) is not None and db.get(CropCycle, crop_id) is not None
                assert db.get(CropCycle, crop_b_id) is not None
            assert client.post("/api/v1/crops", json={"farm_id": farm_a_id, "crop_type": "No auth", "planting_date": "2026-10-15"}).status_code == 401
            assert client.get("/api/v1/crops", headers={"Authorization": "Bearer not-a-jwt"}).status_code == 401
            assert client.post("/api/v1/crops", headers=auth_a, json={"farm_id": farm_a_id, "crop_type": "Bad", "planting_date": "2026-10-15", "status": "growing"}).status_code == 422
            assert client.post("/api/v1/crops", headers=auth_a, json={"farm_id": farm_a_id, "crop_type": "Bad", "planting_date": "2026-10-15", "expected_harvest_date": "2026-10-14"}).status_code == 422
            assert client.post("/api/v1/crops", headers=auth_a, json={"farm_id": farm_a_id, "crop_type": "Bad", "planting_date": "2026-10-15", "plant_count": 0}).status_code == 422
            assert client.put(f"/api/v1/crops/{crop_id}", headers=auth_a, json={"crop_type": "No move", "planting_date": "2026-10-15", "status": "active", "farm_id": farm_b_id}).status_code == 422

            removed = client.delete(f"/api/v1/crops/{crop_id}", headers=auth_a)
            assert removed.status_code == 204 and removed.content == b""
            with SessionLocal() as db:
                assert db.get(CropCycle, crop_id) is None and db.get(Farm, farm_a_id) is not None
                assert db.get(CropCycle, crop_b_id) is not None
            assert client.delete(f"/api/v1/farms/{farm_a_id}", headers=auth_a).status_code == 204
    finally:
        with SessionLocal() as db:
            ids = list(db.scalars(select(User.id).where(User.email.in_(emails))))
            farm_ids = list(db.scalars(select(Farm.id).where(Farm.user_id.in_(ids)))) if ids else []
            if farm_ids:
                db.execute(delete(CropCycle).where(CropCycle.farm_id.in_(farm_ids)))
            if ids:
                db.execute(delete(RefreshToken).where(RefreshToken.user_id.in_(ids)))
                db.execute(delete(Farm).where(Farm.user_id.in_(ids)))
                db.execute(delete(User).where(User.id.in_(ids)))
            db.commit()
            assert not list(db.scalars(select(User).where(User.email.in_(emails))))
            for model, count in before.items():
                assert db.scalar(select(func.count()).select_from(model)) == count
