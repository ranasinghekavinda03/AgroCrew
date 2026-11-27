from datetime import date, datetime, timezone
from unittest.mock import MagicMock

import pytest
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.db.models import CropCycle, CropObservation, Farm, User
from app.schemas.crop_observation import CropObservationCreate
from app.services.crop_observation_service import (
    CropObservationServiceError,
    create_crop_observation,
    get_user_crop_observation,
    list_user_crop_observations,
)


def _seed(db: Session, email: str) -> tuple[User, CropCycle]:
    user = User(name="Service User", email=email, password_hash="test-hash")
    farm = Farm(name="Service Farm")
    crop = CropCycle(crop_type="Rice", planting_date=date(2026, 11, 1))
    user.farms.append(farm)
    farm.crop_cycles.append(crop)
    db.add(user)
    db.commit()
    return user, crop


def _data(notes: str = "Manual note") -> CropObservationCreate:
    return CropObservationCreate(
        observation_date="2026-11-27",
        category="general",
        notes=notes,
    )


def test_service_create_list_detail_and_owner_isolation(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        owner, crop = _seed(db, "service-owner@example.com")
        other, _ = _seed(db, "service-other@example.com")
        created = create_crop_observation(db, owner.id, crop.id, _data("Owned"))
        assert created is not None and created.crop_cycle_id == crop.id
        assert list_user_crop_observations(db, owner.id, crop.id) == [created]
        assert get_user_crop_observation(db, owner.id, crop.id, created.id) is created
        assert create_crop_observation(db, other.id, crop.id, _data()) is None
        assert list_user_crop_observations(db, other.id, crop.id) is None
        assert get_user_crop_observation(db, other.id, crop.id, created.id) is None


def test_service_wrong_parent_and_missing_values_are_hidden(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        owner, first = _seed(db, "service-parent@example.com")
        farm = first.farm
        second = CropCycle(crop_type="Beans", planting_date=date(2026, 11, 2))
        farm.crop_cycles.append(second)
        db.commit()
        created = create_crop_observation(db, owner.id, first.id, _data())
        assert created is not None
        assert get_user_crop_observation(db, owner.id, second.id, created.id) is None
        assert get_user_crop_observation(db, owner.id, first.id, 999_999) is None
        assert list_user_crop_observations(db, owner.id, 999_999) is None


def test_service_timeline_order_and_pagination(
    test_session_factory: sessionmaker[Session],
) -> None:
    with test_session_factory() as db:
        owner, crop = _seed(db, "service-order@example.com")
        stamp = datetime(2026, 11, 27, 12, tzinfo=timezone.utc)
        observations = [
            CropObservation(crop_cycle_id=crop.id, observation_date=date(2026, 11, 26), category="general", notes="older", created_at=stamp, updated_at=stamp),
            CropObservation(crop_cycle_id=crop.id, observation_date=date(2026, 11, 27), category="general", notes="same-1", created_at=stamp, updated_at=stamp),
            CropObservation(crop_cycle_id=crop.id, observation_date=date(2026, 11, 27), category="general", notes="same-2", created_at=stamp, updated_at=stamp),
        ]
        db.add_all(observations)
        db.commit()
        page = list_user_crop_observations(db, owner.id, crop.id, limit=2, offset=0)
        assert page is not None
        assert [item.notes for item in page] == ["same-2", "same-1"]
        second_page = list_user_crop_observations(db, owner.id, crop.id, limit=2, offset=2)
        assert second_page is not None
        assert [item.notes for item in second_page] == ["older"]


@pytest.mark.parametrize("operation", ["create", "list", "get"])
def test_service_rolls_back_and_sanitizes_database_errors(operation: str) -> None:
    db = MagicMock(spec=Session)
    db.scalar.side_effect = SQLAlchemyError("secret SQL details")
    with pytest.raises(CropObservationServiceError) as raised:
        if operation == "create":
            create_crop_observation(db, 1, 1, _data())
        elif operation == "list":
            list_user_crop_observations(db, 1, 1)
        else:
            get_user_crop_observation(db, 1, 1, 1)
    db.rollback.assert_called_once_with()
    assert str(raised.value) == ""


def test_service_commit_failure_rolls_back_and_does_not_retry() -> None:
    db = MagicMock(spec=Session)
    db.scalar.return_value = CropCycle(id=1, farm_id=1, crop_type="Rice", planting_date=date(2026, 1, 1))
    db.commit.side_effect = SQLAlchemyError("secret commit")
    with pytest.raises(CropObservationServiceError):
        create_crop_observation(db, 1, 1, _data())
    db.commit.assert_called_once_with()
    db.rollback.assert_called_once_with()
