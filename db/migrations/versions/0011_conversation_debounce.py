"""persistent per-conversation debounce timer.

Revision ID: 0011
Revises: 0010
"""

from __future__ import annotations

from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE messages
            ADD COLUMN source_channel TEXT NULL,
            ADD COLUMN source_platform_msg_id TEXT NULL,
            ADD CONSTRAINT uq_messages_source_event UNIQUE (source_channel, source_platform_msg_id)
    """)
    op.execute("ALTER TABLE conversations ADD COLUMN next_debounce_at TIMESTAMPTZ NULL")
    op.execute("CREATE INDEX idx_conv_debounce ON conversations (next_debounce_at)")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_conv_debounce")
    op.execute("ALTER TABLE conversations DROP COLUMN IF EXISTS next_debounce_at")
    op.execute("""
        ALTER TABLE messages
            DROP CONSTRAINT IF EXISTS uq_messages_source_event,
            DROP COLUMN IF EXISTS source_platform_msg_id,
            DROP COLUMN IF EXISTS source_channel
    """)
