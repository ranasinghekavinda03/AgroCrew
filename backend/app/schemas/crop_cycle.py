from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt, field_validator, model_validator


CropStatus = Literal["planned", "active", "harvested", "cancelled"]
NOTES_MAX_LENGTH = 10_000


class CropCycleFields(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    crop_type: str = Field(min_length=1, max_length=128)
    variety: str | None = Field(default=None, max_length=128)
    planting_date: date
    expected_harvest_date: date | None = None
    status: CropStatus
    plant_count: StrictInt | None = Field(default=None, gt=0)
    notes: str | None = Field(default=None, max_length=NOTES_MAX_LENGTH)

    @field_validator("planting_date", "expected_harvest_date", mode="before")
    @classmethod
    def accept_iso_calendar_dates_only(cls, value):
        # Pydantic otherwise accepts a datetime string for a date field.
        if value is None:
            return None
        if isinstance(value, date) and not isinstance(value, datetime):
            return value
        if not isinstance(value, str) or len(value) != 10:
            raise ValueError("Date must use the YYYY-MM-DD format.")
        try:
            return date.fromisoformat(value)
        except ValueError:
            raise ValueError("Date must use the YYYY-MM-DD format.") from None

    @field_validator("crop_type")
    @classmethod
    def normalize_crop_type(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Crop type must not be empty.")
        return value

    @field_validator("variety")
    @classmethod
    def normalize_variety(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @model_validator(mode="after")
    def harvest_after_planting(self):
        if self.expected_harvest_date and self.expected_harvest_date < self.planting_date:
            raise ValueError("Expected harvest date must not precede planting date.")
        return self


class CropCycleCreate(CropCycleFields):
    farm_id: StrictInt = Field(gt=0)
    status: CropStatus = "planned"


class CropCycleUpdate(CropCycleFields):
    """Full replacement; omitted optional fields are cleared to null."""


class CropCycleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    farm_id: int
    crop_type: str
    variety: str | None
    planting_date: date
    expected_harvest_date: date | None
    status: CropStatus
    plant_count: int | None
    notes: str | None
    created_at: datetime
    updated_at: datetime
