from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models.crop_cycle import CropCycle
from app.db.models.farm import Farm
from app.schemas.crop_cycle import CropCycleCreate, CropCycleUpdate


class CropCycleServiceError(Exception):
    """A crop operation failed without exposing database details."""


class CropCycleConflictError(CropCycleServiceError):
    """The crop cannot be deleted because dependent data exists."""


def create_crop_cycle(db: Session, owner_id: int, data: CropCycleCreate) -> CropCycle | None:
    try:
        # Locking the parent serializes creation against Farm deletion on PostgreSQL.
        farm = db.scalar(
            select(Farm).where(Farm.id == data.farm_id, Farm.user_id == owner_id).with_for_update()
        )
        if farm is None:
            return None
        crop = CropCycle(**data.model_dump())
        db.add(crop)
        db.commit()
        db.refresh(crop)
        return crop
    except SQLAlchemyError:
        db.rollback()
        raise CropCycleServiceError from None


def list_user_crop_cycles(
    db: Session, owner_id: int, *, limit: int = 100, offset: int = 0, farm_id: int | None = None
) -> list[CropCycle]:
    try:
        query = select(CropCycle).join(Farm).where(Farm.user_id == owner_id)
        if farm_id is not None:
            query = query.where(Farm.id == farm_id)
        return list(db.scalars(query.order_by(CropCycle.created_at.asc(), CropCycle.id.asc()).offset(offset).limit(limit)))
    except SQLAlchemyError:
        db.rollback()
        raise CropCycleServiceError from None


def _owned_crop_query(owner_id: int, crop_id: int):
    return select(CropCycle).join(Farm).where(
        CropCycle.id == crop_id,
        CropCycle.farm_id == Farm.id,
        Farm.user_id == owner_id,
    )


def get_user_crop_cycle(db: Session, owner_id: int, crop_id: int) -> CropCycle | None:
    try:
        return db.scalar(_owned_crop_query(owner_id, crop_id))
    except SQLAlchemyError:
        db.rollback()
        raise CropCycleServiceError from None


def update_user_crop_cycle(
    db: Session, owner_id: int, crop_id: int, data: CropCycleUpdate
) -> CropCycle | None:
    try:
        crop = db.scalar(_owned_crop_query(owner_id, crop_id).with_for_update())
        if crop is None:
            return None
        for field, value in data.model_dump().items():
            setattr(crop, field, value)
        db.commit()
        db.refresh(crop)
        return crop
    except SQLAlchemyError:
        db.rollback()
        raise CropCycleServiceError from None


def delete_user_crop_cycle(db: Session, owner_id: int, crop_id: int) -> bool:
    try:
        crop = db.scalar(_owned_crop_query(owner_id, crop_id).with_for_update())
        if crop is None:
            return False
        db.delete(crop)
        db.commit()
        return True
    except IntegrityError:
        db.rollback()
        raise CropCycleConflictError from None
    except SQLAlchemyError:
        db.rollback()
        raise CropCycleServiceError from None
