"""F3 receive-and-draft orchestrator (spec 01 §3 Sub-task E).

Glues inbound customer message → draft (from a `Drafter` — F1+F2 context injected by the
LLM adapter later) → `policy_gate.decide` → either `sender.send(...)` or a parked
`PendingReply` row scoped to `shop_id`. The two branches are the ONLY outcomes; there is no
side channel that sends without gating.

Identity contract (spec 06 F1 — was a shim before):
  - `customer_id` and `conversation_id` are OURS, already resolved. This module never sees
    a platform's id format. `channels.identity.resolve_conversation` maps
    `(channel, external_user_id)` → our ids; the caller does that before calling here.
  - `conversation_id` is REQUIRED. It used to default to `customer_id` when the caller had
    no conversation model, which was survivable only while `conversation_id` was a bare
    Text column referencing nothing. Spec 06 F0 gave it a composite foreign key, so that
    fallback would now write a customer id into a conversation column and be rejected by
    Postgres at runtime. Requiring the argument turns a runtime FK violation into a caller
    error at the boundary.

Explicitly deferred to Phase 5+:
  - Real F1/F2 context enrichment — the `Drafter` protocol receives just the raw message
    for GĐ0. Layering wiki + API context happens in the `Drafter` implementation, not here.
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
from db.repos import MessageRepo, PendingReplyRepo


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
    conversation_id: str,
    message: str,
    drafter: Drafter,
    sender: ZaloSender,
    session_factory: async_sessionmaker[AsyncSession],
    shop_auto_enabled_intents: frozenset[str],
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
        # Ghi SAU khi gửi thành công, không phải trước (spec 10 H1). `send()` nổ ⇒ ngoại lệ
        # bay lên và KHÔNG có row nào — lịch sử không bao giờ khai một điều chưa xảy ra.
        # Ghi trước sẽ làm AI lượt sau tưởng nó đã trả lời khách rồi, và im lặng.
        async with session_factory() as session:
            await MessageRepo(session, shop_scope=shop_id).append(
                conversation_id=conversation_id,
                customer_id=customer_id,
                role="assistant",
                content=draft.text,
            )
        return ReceiveOutcome(action="auto_send", reason=decision.reason, reply_id=None)

    # Park path — new PendingReply row, shop_id BAKED from repo scope (not caller args).
    #
    # CỐ Ý KHÔNG ghi `messages` ở đây (PRE-1004, Wyatt ký 2026-07-20). `PendingReply` đã là
    # bản ghi của nhánh này, và chưa có worker nào thực sự gửi (`api/inbox.py` approve chỉ
    # flip status). Ghi lúc park hay lúc approve đều là khai "đã gửi" trong khi không ai gửi.
    # Hệ quả đã chấp nhận: reply seller duyệt không vào history cho tới khi worker gửi land.
    # Gate: tests/test_message_history.py::test_park_writes_no_assistant_message.
    reply_id = uuid.uuid4().hex
    async with session_factory() as session:
        repo = PendingReplyRepo(session, shop_scope=shop_id)
        await repo.create(
            reply_id=reply_id,
            conversation_id=conversation_id,
            customer_id=customer_id,
            draft_text=draft.text,
            intent=draft.intent,
            confidence=draft.confidence,
        )
    return ReceiveOutcome(action="park", reason=decision.reason, reply_id=reply_id)
