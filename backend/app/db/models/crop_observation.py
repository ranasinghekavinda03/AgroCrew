from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.db.models.crop_cycle import CropCycle


CROP_OBSERVATION_CATEGORIES = (
    "general",
    "growth",
    "irrigation",
    "pest_or_disease_symptom",
    "soil",
    "other",
)


class CropObservation(Base):
    __tablename__ = "crop_observations"
    __table_args__ = (
        CheckConstraint(
            "category IN ('general', 'growth', 'irrigation', "
            "'pest_or_disease_symptom', 'soil', 'other')",
            name="category_valid",
        ),
        CheckConstraint(
            "length(trim(notes)) > 0",
            name="notes_not_blank",
        ),
        # PostgreSQL can scan this ascending index backward for the API's
        # all-descending timeline order; plain columns remain SQLite-friendly.
        Index(
            "ix_crop_observations_timeline",
            "crop_cycle_id",
            "observation_date",
            "created_at",
            "id",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    crop_cycle_id: Mapped[int] = mapped_column(
        ForeignKey("crop_cycles.id", ondelete="RESTRICT"),
        nullable=False,
    )
    observation_date: Mapped[date] = mapped_column(Date, nullable=False)
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    notes: Mapped[str] = mapped_column(Text, nullable=False)
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

    crop_cycle: Mapped["CropCycle"] = relationship(back_populates="observations")
