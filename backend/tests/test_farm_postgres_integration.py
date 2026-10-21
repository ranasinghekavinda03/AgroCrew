from decimal import Decimal
import os
import time
from uuid import uuid4

import pytest
from sqlalchemy import func, inspect, select
from sqlalchemy.exc import IntegrityError

from app.db.models import Farm, RefreshToken, User
from app.db.session import SessionLocal, engine


pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_POSTGRES_INTEGRATION") != "1",
    reason="Set RUN_POSTGRES_INTEGRATION=1 for the disposable PostgreSQL test.",
)


def test_real_postgres_farm_ownership_constraints_and_cleanup() -> None:
    inspector = inspect(engine)
    assert {"users", "refresh_tokens", "farms"}.issubset(
        inspector.get_table_names()
    )

    suffix = uuid4().hex
    first_email = f"step20-first-{suffix}@example.com"
    second_email = f"step20-second-{suffix}@example.com"
    created_user_ids: list[int] = []

    with SessionLocal() as db:
        users_before = db.scalar(select(func.count()).select_from(User))
        refresh_tokens_before = db.scalar(
            select(func.count()).select_from(RefreshToken)
        )
        farms_before = db.scalar(select(func.count()).select_from(Farm))

        try:
            first = User(
                name="Step 20 First Owner",
                email=first_email,
                password_hash="disposable-integration-hash",
            )
            second = User(
                name="Step 20 Second Owner",
                email=second_email,
                password_hash="disposable-integration-hash",
            )
            db.add_all([first, second])
            db.flush()
            created_user_ids.extend([first.id, second.id])

            green_valley = Farm(
                user_id=first.id,
                name="Green Valley Farm",
                latitude=Decimal("6.927079"),
                longitude=Decimal("79.861244"),
                area_value=Decimal("12.5000"),
                area_unit="acres",
                notes="Disposable Step 20 integration record",
            )
            second_farm = Farm(
                user_id=second.id,
                name="River Bend Farm",
            )
            db.add_all([green_valley, second_farm])
            db.commit()

            persisted = db.scalar(
                select(Farm).where(Farm.id == green_valley.id)
            )
            assert persisted is not None
            assert persisted.user_id == first.id
            assert persisted.name == "Green Valley Farm"
            assert persisted.latitude == Decimal("6.927079")
            assert persisted.longitude == Decimal("79.861244")
            assert persisted.area_value == Decimal("12.5000")
            assert persisted.area_unit == "acres"
            assert persisted.created_at.tzinfo is not None
            assert persisted.updated_at.tzinfo is not None
            assert second_farm.user_id == second.id

            original_updated_at = persisted.updated_at
            time.sleep(0.01)
            persisted.notes = "Updated disposable note"
            db.commit()
            db.refresh(persisted)
            assert persisted.updated_at > original_updated_at

            db.add(
                Farm(
                    user_id=2_147_483_647,
                    name="Orphan Farm",
                )
            )
            with pytest.raises(IntegrityError):
                db.commit()
            db.rollback()

            invalid_measurements = (
                {"latitude": Decimal("90.000001")},
                {"latitude": Decimal("-90.000001")},
                {"longitude": Decimal("180.000001")},
                {"longitude": Decimal("-180.000001")},
                {"area_value": Decimal("0")},
                {"area_value": Decimal("-0.0001")},
            )
            for position, measurements in enumerate(invalid_measurements):
                db.add(
                    Farm(
                        user_id=created_user_ids[0],
                        name=f"Invalid measurement {position}",
                        **measurements,
                    )
                )
                with pytest.raises(IntegrityError):
                    db.commit()
                db.rollback()

            assert db.scalar(
                select(func.count())
                .select_from(Farm)
                .where(Farm.user_id.in_(created_user_ids))
            ) == 2
        finally:
            db.query(User).filter(User.id.in_(created_user_ids)).delete(
                synchronize_session=False
            )
            db.commit()

        assert db.scalar(select(func.count()).select_from(User)) == users_before
        assert (
            db.scalar(select(func.count()).select_from(RefreshToken))
            == refresh_tokens_before
        )
        assert db.scalar(select(func.count()).select_from(Farm)) == farms_before
