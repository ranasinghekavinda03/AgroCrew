from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship, validates

from app.db.base import Base

if TYPE_CHECKING:
    from app.db.models.farm import Farm


CROP_CYCLE_STATUSES = ("planned", "active", "harvested", "cancelled")


class CropCycle(Base):
    __tablename__ = "crop_cycles"
    __table_args__ = (
        CheckConstraint(
            "length(trim(crop_type)) > 0",
            name="crop_type_not_blank",
        ),
        CheckConstraint(
            "expected_harvest_date IS NULL OR expected_harvest_date >= planting_date",
            name="harvest_not_before_planting",
        ),
        CheckConstraint(
            "status IN ('planned', 'active', 'harvested', 'cancelled')",
            name="status_valid",
        ),
        CheckConstraint(
            "plant_count IS NULL OR plant_count > 0",
            name="plant_count_positive",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    farm_id: Mapped[int] = mapped_column(
        ForeignKey("farms.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    crop_type: Mapped[str] = mapped_column(String(128), nullable=False)
    variety: Mapped[str | None] = mapped_column(String(128), nullable=True)
    planting_date: Mapped[date] = mapped_column(Date, nullable=False)
    expected_harvest_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="planned",
        server_default="planned",
    )
    plant_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    farm: Mapped["Farm"] = relationship(back_populates="crop_cycles")

    @validates("crop_type")
    def normalize_crop_type(self, _key: str, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            raise ValueError("Crop type must not be empty.")
        return normalized
