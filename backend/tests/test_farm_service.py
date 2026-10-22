from unittest.mock import MagicMock

import pytest
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models import Farm
from app.schemas.farm import FarmCreate
from app.services.farm_service import (
    FarmConflictError,
    FarmServiceError,
    create_farm,
    delete_user_farm,
    list_user_farms,
)


def test_create_rolls_back_and_sanitizes_database_error() -> None:
    db = MagicMock(spec=Session)
    db.commit.side_effect = SQLAlchemyError("secret database details")

    with pytest.raises(FarmServiceError) as raised:
        create_farm(db, 1, FarmCreate(name="Farm"))

    db.rollback.assert_called_once_with()
    assert str(raised.value) == ""


def test_read_failure_rolls_back_and_sanitizes_database_error() -> None:
    db = MagicMock(spec=Session)
    db.scalars.side_effect = SQLAlchemyError("secret database details")

    with pytest.raises(FarmServiceError) as raised:
        list_user_farms(db, 1)

    db.rollback.assert_called_once_with()
    assert str(raised.value) == ""


def test_delete_integrity_failure_becomes_safe_conflict() -> None:
    db = MagicMock(spec=Session)
    db.scalar.return_value = Farm(id=1, user_id=1, name="Farm")
    db.commit.side_effect = IntegrityError("delete", {}, Exception("secret"))

    with pytest.raises(FarmConflictError) as raised:
        delete_user_farm(db, 1, 1)

    db.rollback.assert_called_once_with()
    assert str(raised.value) == ""


def test_route_hides_service_database_error(
    client,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    registration = client.post(
        "/api/v1/auth/register",
        json={
            "name": "Error Farmer",
            "email": "farm-error@example.com",
            "password": "StrongTestPassword123!",
        },
    )
    assert registration.status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={
            "email": "farm-error@example.com",
            "password": "StrongTestPassword123!",
        },
    ).json()

    def fail(*_args, **_kwargs):
        raise FarmServiceError("secret database details")

    monkeypatch.setattr("app.api.v1.endpoints.farms.create_farm", fail)
    response = client.post(
        "/api/v1/farms",
        headers={"Authorization": f"Bearer {login['access_token']}"},
        json={"name": "Farm"},
    )

    assert response.status_code == 500
    assert response.json() == {
        "detail": "Unable to process the farm operation at this time."
    }
    assert "secret" not in response.text
