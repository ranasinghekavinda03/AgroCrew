from datetime import date
import os
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Date, DateTime, delete, func, inspect, select
from sqlalchemy.exc import IntegrityError

from app.db.models import CropCycle, Farm, RefreshToken, User
from app.db.session import SessionLocal, engine
from app.main import app


pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_POSTGRES_INTEGRATION") != "1",
    reason="Set RUN_POSTGRES_INTEGRATION=1 for disposable PostgreSQL tests.",
)

PASSWORD = "DisposableStep25Password!"


def _register_and_login(
    client: TestClient, email: str, name: str
) -> tuple[int, str]:
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
    return registered.json()["id"], login.json()["access_token"]


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_real_postgres_crop_cycle_integrity_deletion_safety_and_cleanup() -> None:
    _assert_postgres_schema()
    suffix = uuid4().hex
    email_a = f"step25-a-{suffix}@example.com"
    email_b = f"step25-b-{suffix}@example.com"
    emails = [email_a, email_b]

    with SessionLocal() as db:
        counts_before = {
            model: db.scalar(select(func.count()).select_from(model))
            for model in (User, RefreshToken, Farm, CropCycle)
        }

    try:
        with TestClient(app) as client:
            user_a_id, token_a = _register_and_login(
                client, email_a, "Disposable Step 25 Farmer A"
            )
            user_b_id, token_b = _register_and_login(
                client, email_b, "Disposable Step 25 Farmer B"
            )

            farm_a_response = client.post(
                "/api/v1/farms",
                headers=_auth(token_a),
                json={"name": "Step 25 Protected Farm"},
            )
            deletable_response = client.post(
                "/api/v1/farms",
                headers=_auth(token_a),
                json={"name": "Step 25 Deletable Farm"},
            )
            farm_b_response = client.post(
                "/api/v1/farms",
                headers=_auth(token_b),
                json={"name": "Step 25 Other Farm"},
            )
            assert farm_a_response.status_code == 201
            assert deletable_response.status_code == 201
            assert farm_b_response.status_code == 201
            farm_a_id = farm_a_response.json()["id"]
            deletable_id = deletable_response.json()["id"]
            farm_b_id = farm_b_response.json()["id"]

            with SessionLocal() as db:
                tomato = CropCycle(
                    farm_id=farm_a_id,
                    crop_type="Tomato",
                    variety="Roma",
                    planting_date=date(2026, 11, 2),
                    expected_harvest_date=date(2027, 1, 15),
                    status="active",
                    plant_count=120,
                    notes="Disposable Step 25 tomato cycle",
                )
                rice = CropCycle(
                    farm_id=farm_a_id,
                    crop_type="Rice",
                    planting_date=date(2026, 12, 1),
                )
                chilli = CropCycle(
                    farm_id=farm_b_id,
                    crop_type="Chilli",
                    variety="Kochchi",
                    planting_date=date(2026, 10, 15),
                    status="harvested",
                    plant_count=25,
                )
                db.add_all([tomato, rice, chilli])
                db.commit()
                tomato_id, rice_id, chilli_id = tomato.id, rice.id, chilli.id

                persisted = db.get(CropCycle, tomato_id)
                assert persisted is not None
                assert persisted.farm_id == farm_a_id
                assert persisted.crop_type == "Tomato"
                assert persisted.variety == "Roma"
                assert persisted.planting_date == date(2026, 11, 2)
                assert persisted.expected_harvest_date == date(2027, 1, 15)
                assert persisted.status == "active"
                assert persisted.plant_count == 120
                assert persisted.notes == "Disposable Step 25 tomato cycle"
                assert persisted.created_at.tzinfo is not None
                assert persisted.updated_at.tzinfo is not None

                farm_a_cycles = list(
                    db.scalars(
                        select(CropCycle)
                        .where(CropCycle.farm_id == farm_a_id)
                        .order_by(CropCycle.id)
                    )
                )
                assert [cycle.id for cycle in farm_a_cycles] == [tomato_id, rice_id]
                assert tomato_id != rice_id
                assert db.get(CropCycle, chilli_id).farm_id == farm_b_id  # type: ignore[union-attr]

                _assert_integrity_failures_recover(db, farm_a_id)

                loaded_farm = db.get(Farm, farm_a_id)
                assert loaded_farm is not None
                assert len(loaded_farm.crop_cycles) == 2
                db.delete(loaded_farm)
                with pytest.raises(IntegrityError):
                    db.commit()
                db.rollback()
                _assert_protected_records_exist(db, farm_a_id, {tomato_id, rice_id})

                db.expunge_all()
                unloaded_farm = db.get(Farm, farm_a_id)
                assert unloaded_farm is not None
                assert "crop_cycles" not in unloaded_farm.__dict__
                db.delete(unloaded_farm)
                with pytest.raises(IntegrityError):
                    db.commit()
                db.rollback()
                _assert_protected_records_exist(db, farm_a_id, {tomato_id, rice_id})

                user_a = db.get(User, user_a_id)
                assert user_a is not None
                db.delete(user_a)
                with pytest.raises(IntegrityError):
                    db.commit()
                db.rollback()
                assert db.get(User, user_a_id) is not None
                _assert_protected_records_exist(db, farm_a_id, {tomato_id, rice_id})

            wrong_owner = client.delete(
                f"/api/v1/farms/{farm_a_id}", headers=_auth(token_b)
            )
            assert wrong_owner.status_code == 404
            assert wrong_owner.json() == {"detail": "Farm not found."}

            protected_delete = client.delete(
                f"/api/v1/farms/{farm_a_id}", headers=_auth(token_a)
            )
            assert protected_delete.status_code == 409
            assert protected_delete.json() == {
                "detail": "Farm cannot be deleted while related records exist."
            }

            with SessionLocal() as db:
                _assert_protected_records_exist(db, farm_a_id, {tomato_id, rice_id})
                assert db.get(Farm, farm_b_id) is not None
                assert db.get(CropCycle, chilli_id) is not None

            deleted = client.delete(
                f"/api/v1/farms/{deletable_id}", headers=_auth(token_a)
            )
            assert deleted.status_code == 204
            assert deleted.content == b""
            with SessionLocal() as db:
                assert db.get(Farm, deletable_id) is None
                assert db.get(User, user_a_id) is not None
                assert db.get(Farm, farm_b_id) is not None
                assert db.get(User, user_b_id) is not None
    finally:
        with SessionLocal() as db:
            disposable_users = select(User.id).where(User.email.in_(emails))
            user_ids = list(db.scalars(disposable_users))
            if user_ids:
                farm_ids = list(
                    db.scalars(select(Farm.id).where(Farm.user_id.in_(user_ids)))
                )
                if farm_ids:
                    db.execute(delete(CropCycle).where(CropCycle.farm_id.in_(farm_ids)))
                db.execute(delete(User).where(User.id.in_(user_ids)))
                db.commit()

            assert not list(db.scalars(select(User).where(User.email.in_(emails))))
            for model, count in counts_before.items():
                assert db.scalar(select(func.count()).select_from(model)) == count


def _assert_integrity_failures_recover(db, farm_id: int) -> None:
    invalid_values = (
        {"farm_id": 2_147_483_647, "crop_type": "Orphan"},
        {"farm_id": farm_id, "crop_type": "Invalid Status", "status": "growing"},
        {
            "farm_id": farm_id,
            "crop_type": "Invalid Date",
            "expected_harvest_date": date(2026, 11, 1),
        },
        {"farm_id": farm_id, "crop_type": "Invalid Count", "plant_count": 0},
        {"farm_id": farm_id, "crop_type": "Negative Count", "plant_count": -1},
    )
    for values in invalid_values:
        cycle_values = {"planting_date": date(2026, 11, 2), **values}
        db.add(CropCycle(**cycle_values))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.get(Farm, farm_id) is not None


def _assert_protected_records_exist(
    db, farm_id: int, expected_cycle_ids: set[int]
) -> None:
    assert db.get(Farm, farm_id) is not None
    actual_ids = set(
        db.scalars(select(CropCycle.id).where(CropCycle.farm_id == farm_id))
    )
    assert actual_ids == expected_cycle_ids


def _assert_postgres_schema() -> None:
    inspector = inspect(engine)
    assert {"users", "refresh_tokens", "farms", "crop_cycles"}.issubset(
        inspector.get_table_names()
    )
    columns = {column["name"]: column for column in inspector.get_columns("crop_cycles")}
    assert columns["farm_id"]["nullable"] is False
    assert columns["crop_type"]["nullable"] is False
    assert columns["variety"]["nullable"] is True
    assert columns["planting_date"]["nullable"] is False
    assert columns["expected_harvest_date"]["nullable"] is True
    assert columns["status"]["nullable"] is False
    assert columns["plant_count"]["nullable"] is True
    assert isinstance(columns["planting_date"]["type"], Date)
    assert isinstance(columns["expected_harvest_date"]["type"], Date)
    assert isinstance(columns["created_at"]["type"], DateTime)
    assert columns["created_at"]["type"].timezone is True
    assert columns["updated_at"]["type"].timezone is True
    assert inspector.get_pk_constraint("crop_cycles")["constrained_columns"] == ["id"]

    foreign_keys = inspector.get_foreign_keys("crop_cycles")
    assert len(foreign_keys) == 1
    assert foreign_keys[0]["constrained_columns"] == ["farm_id"]
    assert foreign_keys[0]["referred_table"] == "farms"
    assert foreign_keys[0]["referred_columns"] == ["id"]
    assert foreign_keys[0]["options"]["ondelete"] == "RESTRICT"
    assert "ix_crop_cycles_farm_id" in {
        index["name"] for index in inspector.get_indexes("crop_cycles")
    }
    assert {
        "ck_crop_cycles_crop_type_not_blank",
        "ck_crop_cycles_harvest_not_before_planting",
        "ck_crop_cycles_plant_count_positive",
        "ck_crop_cycles_status_valid",
    } == {
        constraint["name"]
        for constraint in inspector.get_check_constraints("crop_cycles")
    }
