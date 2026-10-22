from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models.farm import Farm
from app.schemas.farm import FarmCreate, FarmUpdate


class FarmServiceError(Exception):
    """A farm operation failed without exposing its database details."""


class FarmConflictError(FarmServiceError):
    """The operation conflicts with related database records."""


def create_farm(db: Session, owner_id: int, farm_data: FarmCreate) -> Farm:
    farm = Farm(user_id=owner_id, **farm_data.model_dump())
    try:
        db.add(farm)
        db.commit()
        db.refresh(farm)
        return farm
    except SQLAlchemyError:
        db.rollback()
        raise FarmServiceError from None


def list_user_farms(
    db: Session,
    owner_id: int,
    *,
    limit: int = 100,
    offset: int = 0,
) -> list[Farm]:
    try:
        return list(
            db.scalars(
                select(Farm)
                .where(Farm.user_id == owner_id)
                .order_by(Farm.created_at.asc(), Farm.id.asc())
                .offset(offset)
                .limit(limit)
            )
        )
    except SQLAlchemyError:
        db.rollback()
        raise FarmServiceError from None


def get_user_farm(db: Session, owner_id: int, farm_id: int) -> Farm | None:
    try:
        return db.scalar(_owned_farm_query(owner_id, farm_id))
    except SQLAlchemyError:
        db.rollback()
        raise FarmServiceError from None


def update_user_farm(
    db: Session,
    owner_id: int,
    farm_id: int,
    farm_data: FarmUpdate,
) -> Farm | None:
    try:
        farm = db.scalar(_owned_farm_query(owner_id, farm_id).with_for_update())
        if farm is None:
            return None

        for field, value in farm_data.model_dump().items():
            setattr(farm, field, value)
        db.commit()
        db.refresh(farm)
        return farm
    except SQLAlchemyError:
        db.rollback()
        raise FarmServiceError from None


def delete_user_farm(db: Session, owner_id: int, farm_id: int) -> bool:
    try:
        farm = db.scalar(_owned_farm_query(owner_id, farm_id).with_for_update())
        if farm is None:
            return False

        db.delete(farm)
        db.commit()
        return True
    except IntegrityError:
        db.rollback()
        raise FarmConflictError from None
    except SQLAlchemyError:
        db.rollback()
        raise FarmServiceError from None


def _owned_farm_query(owner_id: int, farm_id: int):
    return select(Farm).where(
        Farm.id == farm_id,
        Farm.user_id == owner_id,
    )
