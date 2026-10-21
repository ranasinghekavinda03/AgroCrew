from decimal import Decimal
import time

import pytest
from sqlalchemy import inspect
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import Farm, User


def _user(email: str) -> User:
    return User(
        name="Farm Model Test User",
        email=email,
        password_hash="tests-only-password-hash",
    )


def test_farm_persists_with_generated_identity_and_optional_fields(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("farm-owner@example.com")
        farm = Farm(user_id=0, name="ග්‍රීන් වැලි Farm")
        user.farms.append(farm)
        db.add(user)
        db.commit()
        db.refresh(farm)

        assert farm.id > 0
        assert farm.user_id == user.id
        assert farm.owner is user
        assert farm.latitude is None
        assert farm.longitude is None
        assert farm.area_value is None
        assert farm.area_unit is None
        assert farm.notes is None
        assert farm.created_at is not None
        assert farm.updated_at is not None


def test_users_can_own_multiple_distinct_farms(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        first = _user("first-farm-owner@example.com")
        second = _user("second-farm-owner@example.com")
        first.farms.extend(
            [
                Farm(name="North Field"),
                Farm(name="South Field"),
            ]
        )
        second.farms.append(Farm(name="River Farm"))
        db.add_all([first, second])
        db.commit()

        assert {farm.name for farm in first.farms} == {
            "North Field",
            "South Field",
        }
        assert [farm.name for farm in second.farms] == ["River Farm"]
        assert all(farm.user_id == first.id for farm in first.farms)
        assert second.farms[0].user_id == second.id


@pytest.mark.parametrize(
    ("values", "constraint_name"),
    [
        ({"latitude": Decimal("90.000001")}, "latitude_range"),
        ({"latitude": Decimal("-90.000001")}, "latitude_range"),
        ({"longitude": Decimal("180.000001")}, "longitude_range"),
        ({"longitude": Decimal("-180.000001")}, "longitude_range"),
        ({"area_value": Decimal("0")}, "area_value_positive"),
        ({"area_value": Decimal("-0.0001")}, "area_value_positive"),
    ],
)
def test_numeric_constraints_reject_invalid_values(
    test_session_factory: sessionmaker[Session],
    values: dict[str, Decimal],
    constraint_name: str,
) -> None:
    with test_session_factory() as db:
        user = _user(f"{constraint_name}-{len(values)}@example.com")
        db.add(user)
        db.flush()
        db.add(Farm(user_id=user.id, name="Invalid Farm", **values))

        with pytest.raises(IntegrityError):
            db.commit()


@pytest.mark.parametrize("missing_field", ["user_id", "name"])
def test_required_columns_are_enforced(
    test_session_factory: sessionmaker[Session],
    missing_field: str,
) -> None:
    with test_session_factory() as db:
        user = _user(f"missing-{missing_field}@example.com")
        db.add(user)
        db.flush()
        values = {"user_id": user.id, "name": "Required Field Farm"}
        values[missing_field] = None
        db.add(Farm(**values))  # type: ignore[arg-type]

        with pytest.raises(IntegrityError):
            db.commit()


def test_updated_at_changes_when_farm_is_updated(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        user = _user("updated-farm-owner@example.com")
        farm = Farm(name="Original Name")
        user.farms.append(farm)
        db.add(user)
        db.commit()
        db.refresh(farm)
        original_updated_at = farm.updated_at

        time.sleep(1.05)
        farm.name = "Updated Name"
        db.commit()
        db.refresh(farm)

        assert farm.updated_at > original_updated_at


def test_farm_metadata_matches_expected_schema(
    test_session_factory: sessionmaker[Session],
) -> None:
    inspector = inspect(test_session_factory.kw["bind"])
    columns = {column["name"]: column for column in inspector.get_columns("farms")}
    checks = {
        constraint["name"]
        for constraint in inspector.get_check_constraints("farms")
    }
    indexes = {index["name"] for index in inspector.get_indexes("farms")}

    assert set(columns) == {
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
    assert columns["user_id"]["nullable"] is False
    assert columns["name"]["nullable"] is False
    assert columns["latitude"]["nullable"] is True
    assert columns["longitude"]["nullable"] is True
    assert columns["area_value"]["nullable"] is True
    assert checks == {
        "ck_farms_area_value_positive",
        "ck_farms_latitude_range",
        "ck_farms_longitude_range",
    }
    assert "ix_farms_user_id" in indexes
