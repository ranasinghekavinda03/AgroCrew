"""Opt-in Crop Observation checks for a verified disposable PostgreSQL database."""
from datetime import date
import os
from uuid import uuid4

import pytest
from sqlalchemy import inspect, select
from sqlalchemy.exc import IntegrityError

from app.db.models import CropCycle, CropObservation, Farm, User
from app.db.session import SessionLocal, engine


pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_POSTGRES_INTEGRATION") != "1",
    reason="Set RUN_POSTGRES_INTEGRATION=1 only for a verified disposable PostgreSQL database.",
)


def test_real_postgres_observation_constraints_index_and_delete_restriction() -> None:
    assert engine.dialect.name == "postgresql"
    inspector = inspect(engine)
    assert "crop_observations" in inspector.get_table_names()
    assert {item["name"] for item in inspector.get_check_constraints("crop_observations")} == {
        "ck_crop_observations_category_valid",
        "ck_crop_observations_notes_not_blank",
    }
    assert {item["name"] for item in inspector.get_indexes("crop_observations")} >= {
        "ix_crop_observations_timeline"
    }
    foreign_key = inspector.get_foreign_keys("crop_observations")[0]
    assert foreign_key["options"]["ondelete"] == "RESTRICT"

    email = f"step28b-{uuid4().hex}@example.com"
    user_id = None
    try:
        with SessionLocal() as db:
            user = User(name="Disposable Step 28B", email=email, password_hash="test-hash")
            farm = Farm(name="Disposable Observation Farm")
            crop = CropCycle(crop_type="Rice", planting_date=date(2026, 11, 1))
            user.farms.append(farm)
            farm.crop_cycles.append(crop)
            crop.observations.append(CropObservation(observation_date=date(2026, 11, 27), category="general", notes="Disposable"))
            db.add(user)
            db.commit()
            user_id, crop_id, observation_id = user.id, crop.id, crop.observations[0].id
            db.expunge_all()
            persisted_crop = db.get(CropCycle, crop_id)
            assert persisted_crop is not None
            db.delete(persisted_crop)
            with pytest.raises(IntegrityError):
                db.commit()
            db.rollback()
            assert db.get(CropObservation, observation_id) is not None
    finally:
        if user_id is not None:
            with SessionLocal() as db:
                user = db.scalar(select(User).where(User.id == user_id))
                if user is not None:
                    observation_ids = select(CropObservation.id).join(CropCycle).join(Farm).where(Farm.user_id == user_id)
                    for observation_id in db.scalars(observation_ids):
                        observation = db.get(CropObservation, observation_id)
                        if observation is not None:
                            db.delete(observation)
                    db.flush()
                    for crop in list(db.scalars(select(CropCycle).join(Farm).where(Farm.user_id == user_id))):
                        db.delete(crop)
                    db.flush()
                    db.delete(user)
                    db.commit()
