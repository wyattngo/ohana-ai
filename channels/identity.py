"""External identity → internal identity (spec 06 Phase F1).

This module exists to kill the shim at `agent/orchestrator.py` that read
`conversation_id or customer_id`. That fallback predates the `conversations` table; after
spec 06 F0 added composite foreign keys it would FK-violate at runtime — a parked reply
would reference a conversation id that is really a customer id and Postgres would reject it.

Placement is deliberate: mapping `(channel, external_user_id)` to our own ids belongs to the
CHANNEL layer, because that is the only layer that knows what a Zalo user id looks like.
The orchestrator should never learn a platform's id format; it receives ids that are already
ours.

Everything here is shop-scoped. The same human messaging two shops produces two customers
and two conversations — see `db.models.Customer` for why that separation is absolute.
"""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from db.models import Conversation, Customer


async def resolve_conversation(
    session: AsyncSession,
    *,
    shop_id: str,
    channel: str,
    external_user_id: str,
    external_thread_id: str | None = None,
) -> tuple[str, str]:
    """Return `(customer_id, conversation_id)`, creating either if this is a first contact.

    Idempotent on `(shop_id, channel, external_user_id)`: a second message from the same
    person reuses the same rows instead of minting a new customer per inbound message.

    The customer insert uses `ON CONFLICT DO NOTHING` against the
    `uq_customers_shop_chan_ext` constraint, then re-selects — so two concurrent inbound
    messages cannot produce duplicate customers.

    KNOWN UNCOVERED (spec 06 F1): the conversation lookup is select-then-insert with no
    unique constraint behind it, so a genuine race could create two conversations for one
    customer. Harmless today because the webhook is not mounted and nothing calls this
    concurrently. Before Spec 03c mounts the webhook, add a unique constraint on
    `(shop_id, customer_id, channel)` and switch this to the same upsert shape as the
    customer above. Do not rely on "it hasn't happened yet".
    """
    if not shop_id:
        raise ValueError("shop_id is required — must come from verified auth, never a payload")
    if not external_user_id:
        raise ValueError("external_user_id is required — refusing to attribute a message to nobody")

    await session.execute(
        pg_insert(Customer)
        .values(
            id=f"cus_{uuid.uuid4().hex[:16]}",
            shop_id=shop_id,
            channel=channel,
            external_id=external_user_id,
        )
        .on_conflict_do_nothing(constraint="uq_customers_shop_chan_ext")
    )
    await session.flush()

    customer_id = (
        await session.execute(
            select(Customer.id)
            .where(Customer.shop_id == shop_id)
            .where(Customer.channel == channel)
            .where(Customer.external_id == external_user_id)
        )
    ).scalar_one()

    conversation_id = (
        await session.execute(
            select(Conversation.id)
            .where(Conversation.shop_id == shop_id)
            .where(Conversation.customer_id == customer_id)
            .where(Conversation.channel == channel)
            .order_by(Conversation.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()

    if conversation_id is None:
        conversation_id = f"cnv_{uuid.uuid4().hex[:16]}"
        session.add(
            Conversation(
                id=conversation_id,
                shop_id=shop_id,
                customer_id=customer_id,
                channel=channel,
                external_thread_id=external_thread_id,
            )
        )

    await session.commit()
    return customer_id, conversation_id
