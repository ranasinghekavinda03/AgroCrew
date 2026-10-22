from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.db.models.user import User
from app.db.session import get_db
from app.schemas.farm import FarmCreate, FarmResponse, FarmUpdate
from app.services.farm_service import (
    FarmConflictError,
    FarmServiceError,
    create_farm,
    delete_user_farm,
    get_user_farm,
    list_user_farms,
    update_user_farm,
)


router = APIRouter(prefix="/farms")
FarmId = Annotated[int, Path(gt=0, description="The farm's generated ID.")]

ERROR_RESPONSES = {
    401: {"description": "Missing or invalid Bearer access token."},
    404: {"description": "The farm does not exist for this owner."},
    422: {"description": "The request data is invalid."},
}


def _service_unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unable to process the farm operation at this time.",
    )


def _farm_not_found() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Farm not found.",
    )


@router.post(
    "",
    response_model=FarmResponse,
    status_code=status.HTTP_201_CREATED,
    responses={401: ERROR_RESPONSES[401], 422: ERROR_RESPONSES[422]},
    summary="Create a farm owned by the authenticated farmer",
)
def create_owned_farm(
    farm_data: FarmCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FarmResponse:
    try:
        farm = create_farm(db, current_user.id, farm_data)
    except FarmServiceError:
        raise _service_unavailable() from None
    return FarmResponse.model_validate(farm)


@router.get(
    "",
    response_model=list[FarmResponse],
    responses={401: ERROR_RESPONSES[401], 422: ERROR_RESPONSES[422]},
    summary="List the authenticated farmer's farms",
    description=(
        "Returns farms ordered by creation time and ID. Limit is bounded to 100; "
        "offset is zero-based."
    ),
)
def list_owned_farms(
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[FarmResponse]:
    try:
        farms = list_user_farms(db, current_user.id, limit=limit, offset=offset)
    except FarmServiceError:
        raise _service_unavailable() from None
    return [FarmResponse.model_validate(farm) for farm in farms]


@router.get(
    "/{farm_id}",
    response_model=FarmResponse,
    responses=ERROR_RESPONSES,
    summary="Get one farm owned by the authenticated farmer",
)
def get_owned_farm(
    farm_id: FarmId,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FarmResponse:
    try:
        farm = get_user_farm(db, current_user.id, farm_id)
    except FarmServiceError:
        raise _service_unavailable() from None
    if farm is None:
        raise _farm_not_found()
    return FarmResponse.model_validate(farm)


@router.put(
    "/{farm_id}",
    response_model=FarmResponse,
    responses=ERROR_RESPONSES,
    summary="Replace one farm owned by the authenticated farmer",
    description=(
        "Name is required. Omitted optional fields are cleared because PUT uses "
        "full-replacement semantics."
    ),
)
def replace_owned_farm(
    farm_id: FarmId,
    farm_data: FarmUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> FarmResponse:
    try:
        farm = update_user_farm(db, current_user.id, farm_id, farm_data)
    except FarmServiceError:
        raise _service_unavailable() from None
    if farm is None:
        raise _farm_not_found()
    return FarmResponse.model_validate(farm)


@router.delete(
    "/{farm_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    responses={
        401: ERROR_RESPONSES[401],
        404: ERROR_RESPONSES[404],
        409: {
            "description": "The farm cannot be deleted while related records exist."
        },
        422: ERROR_RESPONSES[422],
    },
    summary="Delete one farm owned by the authenticated farmer",
    description=(
        "Permanently deletes the current farm record. Future farm-dependent crop "
        "history must prevent deletion rather than being cascade-deleted."
    ),
)
def delete_owned_farm(
    farm_id: FarmId,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    try:
        deleted = delete_user_farm(db, current_user.id, farm_id)
    except FarmConflictError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Farm cannot be deleted while related records exist.",
        ) from None
    except FarmServiceError:
        raise _service_unavailable() from None
    if not deleted:
        raise _farm_not_found()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
