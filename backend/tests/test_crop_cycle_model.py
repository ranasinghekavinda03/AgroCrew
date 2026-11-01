from datetime import date
import time

import pytest
from sqlalchemy import inspect, insert, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import CropCycle, Farm, RefreshToken, User


def _user(email: str) -> User:
    return User(
        name="Crop Model Test User",
        email=email,
        password_hash="tests-only-password-hash",
    )


def _cycle(**overrides: object) -> CropCycle:
    values: dict[str, object] = {
        "crop_type": "Tomato",
        "planting_date": date(2026, 11, 2),
    }
    values.update(overrides)
    return CropCycle(**values)  # type: ignore[arg-type]


def test_crop_cycle_persists_all_fields_and_generated_values(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("crop-fields@example.com")
        farm = Farm(name="Unicode Farm")
        user.farms.append(farm)
        cycle = _cycle(
            crop_type="මිරිස්",
            variety="දේශීය",
            expected_harvest_date=date(2027, 1, 5),
            status="active",
            plant_count=40,
            notes=None,
        )
        farm.crop_cycles.append(cycle)
        db.add(user)
        db.commit()
        db.refresh(cycle)

        assert cycle.id > 0
        assert cycle.farm_id == farm.id
        assert cycle.crop_type == "මිරිස්"
        assert cycle.variety == "දේශීය"
        assert cycle.planting_date == date(2026, 11, 2)
        assert cycle.expected_harvest_date == date(2027, 1, 5)
        assert cycle.status == "active"
        assert cycle.plant_count == 40
        assert cycle.notes is None
        assert cycle.created_at is not None
        assert cycle.updated_at is not None


def test_status_defaults_to_planned_and_optional_fields_are_nullable(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("crop-defaults@example.com")
        farm = Farm(name="Defaults Farm")
        cycle = _cycle()
        farm.crop_cycles.append(cycle)
        user.farms.append(farm)
        db.add(user)
        db.commit()
        db.refresh(cycle)

        assert cycle.status == "planned"
        assert cycle.variety is None
        assert cycle.expected_harvest_date is None
        assert cycle.plant_count is None
        assert cycle.notes is None


@pytest.mark.parametrize("missing_field", ["farm_id", "crop_type", "planting_date"])
def test_required_fields_are_enforced(
    test_session_factory: sessionmaker[Session],
    missing_field: str,
) -> None:
    with test_session_factory() as db:
        user = _user(f"missing-{missing_field}@example.com")
        farm = Farm(name="Required Farm")
        user.farms.append(farm)
        db.add(user)
        db.flush()
        values: dict[str, object] = {
            "farm_id": farm.id,
            "crop_type": "Rice",
            "planting_date": date(2026, 11, 2),
            "status": "planned",
        }
        values[missing_field] = None
        db.add(CropCycle(**values))  # type: ignore[arg-type]

        with pytest.raises(IntegrityError):
            db.commit()


def test_explicit_null_status_is_rejected(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("missing-status@example.com")
        farm = Farm(name="Required Status Farm")
        user.farms.append(farm)
        db.add(user)
        db.flush()
        with pytest.raises(IntegrityError):
            db.execute(
                insert(CropCycle).values(
                    farm_id=farm.id,
                    crop_type="Rice",
                    planting_date=date(2026, 11, 2),
                    status=None,
                )
            )


@pytest.mark.parametrize("crop_type", ["", "   ", "\t\n"])
def test_blank_crop_type_is_rejected(
    test_session_factory: sessionmaker[Session], crop_type: str
) -> None:
    with pytest.raises(ValueError, match="Crop type must not be empty"):
        _cycle(crop_type=crop_type)


@pytest.mark.parametrize("status", ["planned", "active", "harvested", "cancelled"])
def test_valid_statuses_are_accepted(
    test_session_factory: sessionmaker[Session], status: str
) -> None:
    with test_session_factory() as db:
        user = _user(f"{status}@example.com")
        farm = Farm(name=f"{status} Farm")
        user.farms.append(farm)
        farm.crop_cycles.append(_cycle(status=status))
        db.add(user)
        db.commit()
        assert farm.crop_cycles[0].status == status


@pytest.mark.parametrize(
    ("values"),
    [
        {"status": "growing"},
        {"plant_count": 0},
        {"plant_count": -1},
        {"expected_harvest_date": date(2026, 11, 1)},
    ],
)
def test_database_constraints_reject_invalid_values(
    test_session_factory: sessionmaker[Session], values: dict[str, object]
) -> None:
    _assert_invalid_cycle(test_session_factory, **values)


def test_invalid_farm_id_is_rejected_and_rollback_recovers_session(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        db.add(_cycle(farm_id=2_147_483_647))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()

        user = _user("rollback-recovery@example.com")
        user.farms.append(Farm(name="Recovery Farm"))
        db.add(user)
        db.commit()
        assert db.scalar(select(Farm).where(Farm.name == "Recovery Farm")) is not None


def test_farm_supports_multiple_cycles_and_farms_remain_separate(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("multiple-crops@example.com")
        first = Farm(name="First Farm")
        second = Farm(name="Second Farm")
        first.crop_cycles.extend([_cycle(crop_type="Tomato"), _cycle(crop_type="Rice")])
        second.crop_cycles.append(_cycle(crop_type="Potato"))
        user.farms.extend([first, second])
        db.add(user)
        db.commit()

        first_cycles = list(
            db.scalars(select(CropCycle).where(CropCycle.farm_id == first.id))
        )
        second_cycles = list(
            db.scalars(select(CropCycle).where(CropCycle.farm_id == second.id))
        )
        assert {cycle.crop_type for cycle in first_cycles} == {"Tomato", "Rice"}
        assert [cycle.crop_type for cycle in second_cycles] == ["Potato"]
        assert len({cycle.id for cycle in first_cycles + second_cycles}) == 3


def test_updated_at_changes_after_modification(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("crop-update@example.com")
        farm = Farm(name="Update Farm")
        user.farms.append(farm)
        cycle = _cycle()
        farm.crop_cycles.append(cycle)
        db.add(user)
        db.commit()
        db.refresh(cycle)
        original = cycle.updated_at

        time.sleep(1.05)
        cycle.notes = "Updated"
        db.commit()
        db.refresh(cycle)
        assert cycle.updated_at > original


def test_existing_models_and_relationships_remain_mapped(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("existing-mappings@example.com")
        farm = Farm(name="Existing Model Farm")
        user.farms.append(farm)
        db.add(user)
        db.commit()

        assert farm.owner is user
        assert user.farms == [farm]
        assert RefreshToken.__tablename__ == "refresh_tokens"


def test_crop_cycle_metadata_matches_expected_schema(
    test_session_factory: sessionmaker[Session],
) -> None:
    inspector = inspect(test_session_factory.kw["bind"])
    columns = {column["name"]: column for column in inspector.get_columns("crop_cycles")}
    checks = {constraint["name"] for constraint in inspector.get_check_constraints("crop_cycles")}
    indexes = {index["name"] for index in inspector.get_indexes("crop_cycles")}
    foreign_keys = inspector.get_foreign_keys("crop_cycles")

    assert set(columns) == {
        "id", "farm_id", "crop_type", "variety", "planting_date",
        "expected_harvest_date", "status", "plant_count", "notes",
        "created_at", "updated_at",
    }
    assert columns["farm_id"]["nullable"] is False
    assert columns["crop_type"]["nullable"] is False
    assert columns["planting_date"]["nullable"] is False
    assert columns["status"]["nullable"] is False
    assert checks == {
        "ck_crop_cycles_crop_type_not_blank",
        "ck_crop_cycles_harvest_not_before_planting",
        "ck_crop_cycles_plant_count_positive",
        "ck_crop_cycles_status_valid",
    }
    assert "ix_crop_cycles_farm_id" in indexes
    assert foreign_keys[0]["referred_table"] == "farms"
    assert foreign_keys[0]["options"]["ondelete"] == "RESTRICT"


def _assert_invalid_cycle(
    test_session_factory: sessionmaker[Session], **values: object
) -> None:
    with test_session_factory() as db:
        user = _user(f"invalid-{time.time_ns()}@example.com")
        farm = Farm(name="Invalid Cycle Farm")
        user.farms.append(farm)
        farm.crop_cycles.append(_cycle(**values))
        db.add(user)
        with pytest.raises(IntegrityError):
            db.commit()
