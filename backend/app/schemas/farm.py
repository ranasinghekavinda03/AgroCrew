from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


NOTES_MAX_LENGTH = 10_000


class FarmWriteBase(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    name: str = Field(min_length=1, max_length=255)
    latitude: Decimal | None = Field(
        default=None,
        ge=Decimal("-90"),
        le=Decimal("90"),
        max_digits=9,
        decimal_places=6,
    )
    longitude: Decimal | None = Field(
        default=None,
        ge=Decimal("-180"),
        le=Decimal("180"),
        max_digits=10,
        decimal_places=6,
    )
    area_value: Decimal | None = Field(
        default=None,
        gt=0,
        max_digits=14,
        decimal_places=4,
    )
    area_unit: str | None = Field(default=None, max_length=32)
    notes: str | None = Field(default=None, max_length=NOTES_MAX_LENGTH)

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Name must not be empty.")
        return normalized

    @field_validator("area_unit")
    @classmethod
    def normalize_area_unit(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            raise ValueError("Area unit must not be empty when provided.")
        return normalized


class FarmCreate(FarmWriteBase):
    """Fields accepted when creating a farm; ownership comes from the JWT."""


class FarmUpdate(FarmWriteBase):
    """Full replacement payload.

    Name must be supplied. Optional fields omitted from a PUT request receive
    their default of None, which clears the corresponding persisted value.
    """


class FarmResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    name: str
    latitude: Decimal | None
    longitude: Decimal | None
    area_value: Decimal | None
    area_unit: str | None
    notes: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("latitude", "longitude", "area_value", when_used="json")
    def serialize_decimal(self, value: Decimal | None) -> float | None:
        return float(value) if value is not None else None
