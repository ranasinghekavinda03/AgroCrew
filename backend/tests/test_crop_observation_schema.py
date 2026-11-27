from datetime import date

import pytest
from pydantic import ValidationError

from app.schemas.crop_observation import CropObservationCreate


VALID_CATEGORIES = (
    "general",
    "growth",
    "irrigation",
    "pest_or_disease_symptom",
    "soil",
    "other",
)


@pytest.mark.parametrize("category", VALID_CATEGORIES)
def test_create_schema_accepts_each_category(category: str) -> None:
    value = CropObservationCreate(
        observation_date="2026-11-27",
        category=category,
        notes="  Healthy growth 🌱  ",
    )
    assert value.category == category
    assert value.notes == "Healthy growth 🌱"


@pytest.mark.parametrize("category", ["", "GENERAL", "disease", "weather", None])
def test_create_schema_rejects_invalid_categories(category: object) -> None:
    with pytest.raises(ValidationError):
        CropObservationCreate(
            observation_date="2026-11-27",
            category=category,
            notes="Note",
        )


@pytest.mark.parametrize("notes", [None, "", "   ", "\t\r\n"])
def test_create_schema_requires_nonblank_notes(notes: object) -> None:
    payload = {
        "observation_date": "2026-11-27",
        "category": "general",
    }
    if notes is not None:
        payload["notes"] = notes
    with pytest.raises(ValidationError):
        CropObservationCreate.model_validate(payload)


@pytest.mark.parametrize("length", [1, 10_000])
def test_create_schema_accepts_notes_boundaries(length: int) -> None:
    value = CropObservationCreate(
        observation_date="2026-11-27",
        category="general",
        notes="🌱" * length,
    )
    assert len(value.notes) == length


def test_create_schema_rejects_notes_over_limit_after_trimming() -> None:
    with pytest.raises(ValidationError):
        CropObservationCreate(
            observation_date="2026-11-27",
            category="general",
            notes=f"  {'x' * 10_001}  ",
        )


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("2024-02-29", date(2024, 2, 29)),
        ("2099-12-31", date(2099, 12, 31)),
        (date(2026, 11, 27), date(2026, 11, 27)),
    ],
)
def test_create_schema_accepts_exact_dates_and_future_dates(raw, expected: date) -> None:
    value = CropObservationCreate(
        observation_date=raw,
        category="general",
        notes="Note",
    )
    assert value.observation_date == expected


@pytest.mark.parametrize(
    "raw",
    [
        "2023-02-29",
        "2026-02-30",
        "2026-1-01",
        "2026-11-27T00:00:00",
        "2026-11-27T00:00:00Z",
        20261127,
    ],
)
def test_create_schema_rejects_non_calendar_date_inputs(raw: object) -> None:
    with pytest.raises(ValidationError):
        CropObservationCreate(
            observation_date=raw,
            category="general",
            notes="Note",
        )


@pytest.mark.parametrize(
    "field",
    ["id", "crop_cycle_id", "farm_id", "user_id", "created_at", "updated_at"],
)
def test_create_schema_forbids_server_and_ownership_fields(field: str) -> None:
    with pytest.raises(ValidationError):
        CropObservationCreate.model_validate(
            {
                "observation_date": "2026-11-27",
                "category": "general",
                "notes": "Note",
                field: 1,
            }
        )
