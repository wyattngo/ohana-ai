"""F3 receive-and-draft orchestrator (spec 01 §3 Sub-task E).

Glues inbound customer message → draft (from a `Drafter` — F1+F2 context injected by the
LLM adapter later) → `policy_gate.decide` → either `sender.send(...)` or a parked
`PendingReply` row scoped to `shop_id`. The two branches are the ONLY outcomes; there is no
side channel that sends without gating.

Explicitly deferred to Phase 5+:
  - Real F1/F2 context enrichment — the `Drafter` protocol receives just the raw message
    for GĐ0. Layering wiki + API context happens in the `Drafter` implementation, not here.
  - Conversation/customer normalization — `customer_id` and `conversation_id` are opaque
    strings (defaults to customer_id when the caller doesn't have a real conversation model
    yet). Wiring these into a normalized schema is deferred to when shops/customers land.
  - Auth wire — the caller MUST supply `shop_id` from `auth.identity.Identity.shop_id`.
    This module cannot verify it; if the caller passes an unverified value, that's an S1
    breach caught upstream (webhook layer / API dependency).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Literal, Protocol

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent.policy_gate import DraftContext, decide
from bridge.zalo_sender import ZaloSender
from db.repos import PendingReplyRepo


class _Draft(Protocol):
    text: str
    intent: str
    confidence: float


class Drafter(Protocol):
    async def draft(self, *, shop_id: str, customer_id: str, message: str) -> _Draft: ...


@dataclass(frozen=True)
class ReceiveOutcome:
    action: Literal["auto_send", "park"]
    reason: str
    reply_id: str | None  # set only for park; None for auto_send


async def receive_and_draft(
    *,
    shop_id: str,
    customer_id: str,
    message: str,
    drafter: Drafter,
    sender: ZaloSender,
    session_factory: async_sessionmaker[AsyncSession],
    shop_auto_enabled_intents: frozenset[str],
    conversation_id: str | None = None,
) -> ReceiveOutcome:
    """Draft → decide → send OR park. Returns the outcome for the caller to log/telemetrize.

    `shop_id` MUST come from verified auth; the sender is called with the SAME `shop_id`
    (no way to redirect a send to another shop). Park path writes ONLY to a repo scoped to
    the same `shop_id` — no cross-shop mutation possible even under a buggy caller.

    `shop_auto_enabled_intents` is the shop-level opt-in set for auto-send. If the intent
    the drafter emits isn't in this set, the gate parks even at high confidence.
    """
    draft = await drafter.draft(shop_id=shop_id, customer_id=customer_id, message=message)

    decision = decide(
        DraftContext(
            confidence=draft.confidence,
            intent=draft.intent,
            shop_auto_enabled_for_intent=(draft.intent in shop_auto_enabled_intents),
        )
    )

    if decision.action == "auto_send":
        await sender.send(shop_id=shop_id, customer_id=customer_id, text=draft.text)
        return ReceiveOutcome(action="auto_send", reason=decision.reason, reply_id=None)

    # Park path — new PendingReply row, shop_id BAKED from repo scope (not caller args).
    reply_id = uuid.uuid4().hex
    async with session_factory() as session:
        repo = PendingReplyRepo(session, shop_scope=shop_id)
        await repo.create(
            reply_id=reply_id,
            conversation_id=conversation_id or customer_id,
            customer_id=customer_id,
            draft_text=draft.text,
            intent=draft.intent,
            confidence=draft.confidence,
        )
    return ReceiveOutcome(action="park", reason=decision.reason, reply_id=reply_id)
