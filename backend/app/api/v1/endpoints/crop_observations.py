from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.db.models.user import User
from app.db.session import get_db
from app.schemas.crop_observation import CropObservationCreate, CropObservationResponse
from app.services.crop_observation_service import (
    CropObservationServiceError,
    create_crop_observation,
    get_user_crop_observation,
    list_user_crop_observations,
)


router = APIRouter(prefix="/crops/{crop_cycle_id}/observations")
CropId = Annotated[int, Path(gt=0, description="The crop cycle's generated ID.")]
ObservationId = Annotated[
    int,
    Path(gt=0, description="The crop observation's generated ID."),
]

ERROR_RESPONSES = {
    401: {"description": "Missing or invalid Bearer access token."},
    404: {"description": "The crop or observation does not exist for this owner."},
    422: {"description": "The request data is invalid."},
}


def _crop_not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="Crop not found.")


def _observation_not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="Observation not found.")


def _unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unable to process the observation operation at this time.",
    )


@router.post(
    "",
    response_model=CropObservationResponse,
    status_code=status.HTTP_201_CREATED,
    responses=ERROR_RESPONSES,
    summary="Create a manual observation for an owned crop cycle",
)
def create_owned_crop_observation(
    crop_cycle_id: CropId,
    data: CropObservationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CropObservationResponse:
    try:
        observation = create_crop_observation(
            db,
            current_user.id,
            crop_cycle_id,
            data,
        )
    except CropObservationServiceError:
        raise _unavailable() from None
    if observation is None:
        raise _crop_not_found()
    return CropObservationResponse.model_validate(observation)


@router.get(
    "",
    response_model=list[CropObservationResponse],
    responses=ERROR_RESPONSES,
    summary="List manual observations for an owned crop cycle",
    description=(
        "Results are ordered by observation date, creation time, and ID, all "
        "descending. Limit is bounded to 100; offset is zero-based."
    ),
)
def list_owned_crop_observations(
    crop_cycle_id: CropId,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[CropObservationResponse]:
    try:
        observations = list_user_crop_observations(
            db,
            current_user.id,
            crop_cycle_id,
            limit=limit,
            offset=offset,
        )
    except CropObservationServiceError:
        raise _unavailable() from None
    if observations is None:
        raise _crop_not_found()
    return [CropObservationResponse.model_validate(item) for item in observations]


@router.get(
    "/{observation_id}",
    response_model=CropObservationResponse,
    responses=ERROR_RESPONSES,
    summary="Get one manual observation for an owned crop cycle",
)
def get_owned_crop_observation(
    crop_cycle_id: CropId,
    observation_id: ObservationId,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CropObservationResponse:
    try:
        observation = get_user_crop_observation(
            db,
            current_user.id,
            crop_cycle_id,
            observation_id,
        )
    except CropObservationServiceError:
        raise _unavailable() from None
    if observation is None:
        raise _observation_not_found()
    return CropObservationResponse.model_validate(observation)
