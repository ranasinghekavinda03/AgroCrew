from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


CropObservationCategory = Literal[
    "general",
    "growth",
    "irrigation",
    "pest_or_disease_symptom",
    "soil",
    "other",
]
NOTES_MAX_LENGTH = 10_000


class CropObservationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    observation_date: date
    category: CropObservationCategory
    notes: str = Field(min_length=1, max_length=NOTES_MAX_LENGTH)

    @field_validator("observation_date", mode="before")
    @classmethod
    def accept_iso_calendar_date_only(cls, value):
        if isinstance(value, date) and not isinstance(value, datetime):
            return value
        if not isinstance(value, str) or len(value) != 10:
            raise ValueError("Date must use the YYYY-MM-DD format.")
        try:
            return date.fromisoformat(value)
        except ValueError:
            raise ValueError("Date must use the YYYY-MM-DD format.") from None

    @field_validator("notes", mode="before")
    @classmethod
    def normalize_notes(cls, value):
        if isinstance(value, str):
            return value.strip()
        return value


class CropObservationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    crop_cycle_id: int
    observation_date: date
    category: CropObservationCategory
    notes: str
    created_at: datetime
    updated_at: datetime
