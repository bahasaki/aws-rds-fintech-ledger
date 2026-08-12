"""initial ledger schema: accounts, transactions, entries

Revision ID: 772957eac988
Revises:
Create Date: 2026-08-11

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "772957eac988"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    account_type = postgresql.ENUM(
        "asset", "liability", "equity", "revenue", "expense",
        name="account_type",
    )
    account_type.create(op.get_bind())

    op.create_table(
        "accounts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("account_type", account_type, nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default="USD"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "transactions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("description", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )

    op.create_table(
        "entries",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "transaction_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("transactions.id"),
            nullable=False,
        ),
        sa.Column(
            "account_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("accounts.id"),
            nullable=False,
        ),
        # NUMERIC(19,4): fixed-point, never float — avoids rounding
        # errors on monetary amounts.
        sa.Column("amount", sa.Numeric(precision=19, scale=4), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
    )

    # Speeds up the common query pattern "all entries for account X"
    # (e.g. computing a running balance) — without this index that
    # query does a full table scan as the entries table grows.
    op.create_index("ix_entries_account_id", "entries", ["account_id"])
    op.create_index("ix_entries_transaction_id", "entries", ["transaction_id"])


def downgrade() -> None:
    op.drop_index("ix_entries_transaction_id", table_name="entries")
    op.drop_index("ix_entries_account_id", table_name="entries")
    op.drop_table("entries")
    op.drop_table("transactions")
    op.drop_table("accounts")

    account_type = postgresql.ENUM(
        "asset", "liability", "equity", "revenue", "expense",
        name="account_type",
    )
    account_type.drop(op.get_bind())
