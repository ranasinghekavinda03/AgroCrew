from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.db.models.crop_cycle import CropCycle
from app.db.models.crop_observation import CropObservation
from app.db.models.farm import Farm
from app.schemas.crop_observation import CropObservationCreate


class CropObservationServiceError(Exception):
    """An observation operation failed without exposing database details."""


def _owned_crop_query(owner_id: int, crop_cycle_id: int):
    return select(CropCycle).join(Farm).where(
        CropCycle.id == crop_cycle_id,
        CropCycle.farm_id == Farm.id,
        Farm.user_id == owner_id,
    )


def create_crop_observation(
    db: Session,
    owner_id: int,
    crop_cycle_id: int,
    data: CropObservationCreate,
) -> CropObservation | None:
    try:
        crop = db.scalar(
            _owned_crop_query(owner_id, crop_cycle_id).with_for_update()
        )
        if crop is None:
            return None

        observation = CropObservation(
            crop_cycle_id=crop.id,
            **data.model_dump(),
        )
        db.add(observation)
        db.commit()
        db.refresh(observation)
        return observation
    except SQLAlchemyError:
        db.rollback()
        raise CropObservationServiceError from None


def list_user_crop_observations(
    db: Session,
    owner_id: int,
    crop_cycle_id: int,
    *,
    limit: int = 100,
    offset: int = 0,
) -> list[CropObservation] | None:
    try:
        if db.scalar(_owned_crop_query(owner_id, crop_cycle_id)) is None:
            return None

        return list(
            db.scalars(
                select(CropObservation)
                .where(CropObservation.crop_cycle_id == crop_cycle_id)
                .order_by(
                    CropObservation.observation_date.desc(),
                    CropObservation.created_at.desc(),
                    CropObservation.id.desc(),
                )
                .offset(offset)
                .limit(limit)
            )
        )
    except SQLAlchemyError:
        db.rollback()
        raise CropObservationServiceError from None


def get_user_crop_observation(
    db: Session,
    owner_id: int,
    crop_cycle_id: int,
    observation_id: int,
) -> CropObservation | None:
    try:
        return db.scalar(
            select(CropObservation)
            .join(CropCycle)
            .join(Farm)
            .where(
                CropObservation.id == observation_id,
                CropObservation.crop_cycle_id == crop_cycle_id,
                CropCycle.id == crop_cycle_id,
                CropCycle.farm_id == Farm.id,
                Farm.user_id == owner_id,
            )
        )
    except SQLAlchemyError:
        db.rollback()
        raise CropObservationServiceError from None
