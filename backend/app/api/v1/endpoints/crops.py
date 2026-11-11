from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_current_user
from app.db.models.user import User
from app.db.session import get_db
from app.schemas.crop_cycle import CropCycleCreate, CropCycleResponse, CropCycleUpdate
from app.services.crop_cycle_service import (
    CropCycleConflictError,
    CropCycleServiceError,
    create_crop_cycle,
    delete_user_crop_cycle,
    get_user_crop_cycle,
    list_user_crop_cycles,
    update_user_crop_cycle,
)
from app.services.farm_service import FarmServiceError, get_user_farm


router = APIRouter(prefix="/crops")
CropId = Annotated[int, Path(gt=0, description="The crop cycle's generated ID.")]
ERROR_RESPONSES = {
    401: {"description": "Missing or invalid Bearer access token."},
    404: {"description": "The crop or farm does not exist for this owner."},
    422: {"description": "The request data is invalid."},
}


def _not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="Crop not found.")


def _unavailable() -> HTTPException:
    return HTTPException(status_code=500, detail="Unable to process the crop operation at this time.")


@router.post("", response_model=CropCycleResponse, status_code=201,
             responses={401: ERROR_RESPONSES[401], 404: ERROR_RESPONSES[404], 422: ERROR_RESPONSES[422]},
             summary="Create a crop cycle on an owned farm")
def create_owned_crop(data: CropCycleCreate, current_user: User = Depends(get_current_user),
                      db: Session = Depends(get_db)) -> CropCycleResponse:
    try:
        crop = create_crop_cycle(db, current_user.id, data)
    except CropCycleServiceError:
        raise _unavailable() from None
    if crop is None:
        raise HTTPException(status_code=404, detail="Farm not found.")
    return CropCycleResponse.model_validate(crop)


@router.get("", response_model=list[CropCycleResponse], responses={401: ERROR_RESPONSES[401], 404: ERROR_RESPONSES[404], 422: ERROR_RESPONSES[422]},
            summary="List the authenticated farmer's crop cycles",
            description="Limit is bounded to 100; offset is zero-based. Results are ordered by creation time and ID. An optional farm_id must belong to the authenticated farmer.")
def list_owned_crops(limit: Annotated[int, Query(ge=1, le=100)] = 100,
                     offset: Annotated[int, Query(ge=0)] = 0,
                     farm_id: Annotated[int | None, Query(gt=0)] = None,
                     current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[CropCycleResponse]:
    try:
        if farm_id is not None and get_user_farm(db, current_user.id, farm_id) is None:
            raise HTTPException(status_code=404, detail="Farm not found.")
        crops = list_user_crop_cycles(db, current_user.id, limit=limit, offset=offset, farm_id=farm_id)
    except FarmServiceError:
        raise _unavailable() from None
    except CropCycleServiceError:
        raise _unavailable() from None
    return [CropCycleResponse.model_validate(crop) for crop in crops]


@router.get("/{crop_cycle_id}", response_model=CropCycleResponse, responses=ERROR_RESPONSES,
            summary="Get one crop cycle owned by the authenticated farmer")
def get_owned_crop(crop_cycle_id: CropId, current_user: User = Depends(get_current_user),
                   db: Session = Depends(get_db)) -> CropCycleResponse:
    try:
        crop = get_user_crop_cycle(db, current_user.id, crop_cycle_id)
    except CropCycleServiceError:
        raise _unavailable() from None
    if crop is None:
        raise _not_found()
    return CropCycleResponse.model_validate(crop)


@router.put("/{crop_cycle_id}", response_model=CropCycleResponse, responses=ERROR_RESPONSES,
            summary="Replace one crop cycle owned by the authenticated farmer",
            description="PUT replaces all writable crop fields. Omitted optional fields are cleared. Farm ownership is immutable. Supported statuses are enum validation only; lifecycle transitions are not enforced.")
def replace_owned_crop(crop_cycle_id: CropId, data: CropCycleUpdate,
                       current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> CropCycleResponse:
    try:
        crop = update_user_crop_cycle(db, current_user.id, crop_cycle_id, data)
    except CropCycleServiceError:
        raise _unavailable() from None
    if crop is None:
        raise _not_found()
    return CropCycleResponse.model_validate(crop)


@router.delete("/{crop_cycle_id}", status_code=204, response_class=Response,
               responses={401: ERROR_RESPONSES[401], 404: ERROR_RESPONSES[404], 409: {"description": "The crop cannot be deleted while related records exist."}, 422: ERROR_RESPONSES[422]},
               summary="Delete one crop cycle owned by the authenticated farmer")
def delete_owned_crop(crop_cycle_id: CropId, current_user: User = Depends(get_current_user),
                      db: Session = Depends(get_db)) -> Response:
    try:
        deleted = delete_user_crop_cycle(db, current_user.id, crop_cycle_id)
    except CropCycleConflictError:
        raise HTTPException(status_code=409, detail="Crop cannot be deleted while related records exist.") from None
    except CropCycleServiceError:
        raise _unavailable() from None
    if not deleted:
        raise _not_found()
    return Response(status_code=204)
