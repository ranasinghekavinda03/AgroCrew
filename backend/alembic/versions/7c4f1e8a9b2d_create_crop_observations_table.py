"""create_crop_observations_table

Revision ID: 7c4f1e8a9b2d
Revises: 2a688eee651b
Create Date: 2026-11-27 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "7c4f1e8a9b2d"
down_revision: Union[str, Sequence[str], None] = "2a688eee651b"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create the manual crop-observation table and timeline index."""
    op.create_table(
        "crop_observations",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("crop_cycle_id", sa.Integer(), nullable=False),
        sa.Column("observation_date", sa.Date(), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "category IN ('general', 'growth', 'irrigation', "
            "'pest_or_disease_symptom', 'soil', 'other')",
            name=op.f("ck_crop_observations_category_valid"),
        ),
        sa.CheckConstraint(
            "length(trim(notes)) > 0",
            name=op.f("ck_crop_observations_notes_not_blank"),
        ),
        sa.ForeignKeyConstraint(
            ["crop_cycle_id"],
            ["crop_cycles.id"],
            name=op.f("fk_crop_observations_crop_cycle_id_crop_cycles"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop_observations")),
    )
    op.create_index(
        "ix_crop_observations_timeline",
        "crop_observations",
        ["crop_cycle_id", "observation_date", "created_at", "id"],
        unique=False,
    )


def downgrade() -> None:
    """Remove only the manual crop-observation objects."""
    op.drop_index(
        "ix_crop_observations_timeline",
        table_name="crop_observations",
    )
    op.drop_table("crop_observations")
