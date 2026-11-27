from datetime import date, datetime, timezone

import pytest
from sqlalchemy import Date, DateTime, inspect, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import CropCycle, CropObservation, Farm, User


def _graph(email: str = "observation-model@example.com") -> tuple[User, Farm, CropCycle]:
    user = User(name="Observation Model User", email=email, password_hash="test-hash")
    farm = Farm(name="Observation Model Farm")
    crop = CropCycle(crop_type="Tomato", planting_date=date(2026, 11, 1))
    user.farms.append(farm)
    farm.crop_cycles.append(crop)
    return user, farm, crop


def test_observation_persists_unicode_relationship_and_timestamps(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user, _, crop = _graph()
        observation = CropObservation(
            observation_date=date(2026, 11, 27),
            category="growth",
            notes="මිරිස් வளர்ச்சி 🌱",
        )
        crop.observations.append(observation)
        db.add(user)
        db.commit()
        db.refresh(observation)

        assert observation.id > 0
        assert observation.crop_cycle_id == crop.id
        assert observation.crop_cycle is crop
        assert crop.observations == [observation]
        assert observation.notes == "මිරිස් வளர்ச்சி 🌱"
        assert observation.created_at is not None
        assert observation.updated_at is not None


def test_observation_metadata_matches_contract(
    test_session_factory: sessionmaker[Session],
) -> None:
    inspector = inspect(test_session_factory.kw["bind"])
    columns = {column["name"]: column for column in inspector.get_columns("crop_observations")}
    assert set(columns) == {
        "id", "crop_cycle_id", "observation_date", "category", "notes",
        "created_at", "updated_at",
    }
    assert inspector.get_pk_constraint("crop_observations")["constrained_columns"] == ["id"]
    assert columns["crop_cycle_id"]["nullable"] is False
    assert isinstance(columns["observation_date"]["type"], Date)
    assert isinstance(columns["created_at"]["type"], DateTime)
    checks = {item["name"] for item in inspector.get_check_constraints("crop_observations")}
    assert checks == {
        "ck_crop_observations_category_valid",
        "ck_crop_observations_notes_not_blank",
    }
    foreign_keys = inspector.get_foreign_keys("crop_observations")
    assert len(foreign_keys) == 1
    assert foreign_keys[0]["constrained_columns"] == ["crop_cycle_id"]
    assert foreign_keys[0]["referred_table"] == "crop_cycles"
    assert foreign_keys[0]["options"]["ondelete"] == "RESTRICT"
    indexes = {item["name"]: item for item in inspector.get_indexes("crop_observations")}
    assert indexes["ix_crop_observations_timeline"]["column_names"] == [
        "crop_cycle_id", "observation_date", "created_at", "id",
    ]


@pytest.mark.parametrize(
    ("category", "notes", "crop_cycle_id"),
    [
        ("diagnosis", "Note", None),
        ("general", "   ", None),
        ("general", "Note", 2_147_483_647),
    ],
)
def test_database_rejects_invalid_observations_and_session_recovers(
    test_session_factory: sessionmaker[Session],
    category: str,
    notes: str,
    crop_cycle_id: int | None,
) -> None:
    with test_session_factory() as db:
        user, _, crop = _graph(f"invalid-{category}-{crop_cycle_id}@example.com")
        db.add(user)
        db.flush()
        observation = CropObservation(
            crop_cycle_id=crop.id if crop_cycle_id is None else crop_cycle_id,
            observation_date=date(2026, 11, 27),
            category=category,
            notes=notes,
        )
        db.add(observation)
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()

        assert db.scalar(select(User).where(User.email == user.email)) is None
        recovery, _, _ = _graph(f"recovery-{category}-{crop_cycle_id}@example.com")
        db.add(recovery)
        db.commit()
        assert recovery.id > 0


def test_crop_delete_is_restricted_without_orm_cascade(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user, _, crop = _graph("restrict@example.com")
        crop.observations.append(
            CropObservation(
                observation_date=date(2026, 11, 27),
                category="general",
                notes="Keep history",
            )
        )
        db.add(user)
        db.commit()
        crop_id = crop.id
        observation_id = crop.observations[0].id
        db.expunge_all()

        unloaded_crop = db.get(CropCycle, crop_id)
        assert unloaded_crop is not None
        assert "observations" not in unloaded_crop.__dict__
        db.delete(unloaded_crop)
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.get(CropCycle, crop_id) is not None
        assert db.get(CropObservation, observation_id) is not None


def test_explicit_timestamps_support_deterministic_ties(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user, _, crop = _graph("timestamps@example.com")
        db.add(user)
        db.flush()
        stamp = datetime(2026, 11, 27, 12, tzinfo=timezone.utc)
        db.add(
            CropObservation(
                crop_cycle_id=crop.id,
                observation_date=date(2026, 11, 27),
                category="general",
                notes="Timestamp",
                created_at=stamp,
                updated_at=stamp,
            )
        )
        db.commit()
