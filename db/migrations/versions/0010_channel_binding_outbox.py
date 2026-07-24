"""verified channel bindings and transactional webhook outbox.

Revision ID: 0010
Revises: 0009
"""

from __future__ import annotations

from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE shop_channel_binding (
            channel TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            page_id TEXT NOT NULL,
            shop_id TEXT NOT NULL REFERENCES shops (id),
            verified_at TIMESTAMPTZ NULL,
            PRIMARY KEY (channel, endpoint, page_id)
        )
    """)
    op.execute("""
        CREATE TABLE webhook_outbox (
            id BIGSERIAL PRIMARY KEY,
            channel TEXT NOT NULL,
            platform_msg_id TEXT NOT NULL,
            shop_id TEXT NOT NULL,
            payload JSONB NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending'
                CONSTRAINT ck_webhook_outbox_status CHECK (status IN ('pending', 'delivered')),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            delivered_at TIMESTAMPTZ NULL,
            CONSTRAINT uq_webhook_outbox_event UNIQUE (channel, platform_msg_id)
        )
    """)
    op.execute("CREATE INDEX idx_webhook_outbox_pending ON webhook_outbox (status, id)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS webhook_outbox")
    op.execute("DROP TABLE IF EXISTS shop_channel_binding")
