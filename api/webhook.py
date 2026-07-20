"""Inbound webhook — channel-agnostic (spec 06 Phase F1; was platform-specific in spec 01).

Route shape is `/webhook/{channel}/{external_id}`: `{channel}` selects an adapter from the
registry the caller passes in, `{external_id}` is the per-shop endpoint id that platform's
gateway was configured with. Nothing in this module knows which platforms exist — adding one
means registering an adapter, not editing request handling (roadmap §5.2.1).

Still NOT mounted in `app/main.py`: there is no concrete `Drafter` implementation yet, and
mounting would expose a path that reaches the draft engine. `enabled=False` is a second,
independent guard so even a mounted router refuses by default until PRE-004 clears.

`shop_id` is DERIVED from `(channel, external_id)` via lookup. The request body is untrusted
and MUST NOT supply a shop_id claim (R1.1 extended) — note the body is handed straight to the
adapter's parser, which only ever reads message content, never tenancy.

When PRE-004 lands: verify the platform signature over the RAW body before parsing.
"""

from __future__ import annotations

from typing import Any, Protocol

from fastapi import APIRouter, Body, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent.orchestrator import ReceiveOutcome, receive_and_draft
from channels.base import InboundChannel, OutboundChannel
from channels.identity import resolve_conversation
from db.repos import MessageRepo


class _Drafter(Protocol):
    async def draft(self, *, shop_id: str, customer_id: str, message: str): ...  # type: ignore[no-untyped-def]  # returns _Draft


class _Channel(InboundChannel, OutboundChannel, Protocol):
    """A channel usable on this route must both parse inbound and send outbound."""


def build_router(
    drafter: _Drafter,
    session_factory: async_sessionmaker[AsyncSession],
    *,
    channels: dict[str, _Channel],
    endpoint_to_shop: dict[tuple[str, str], str],
    shop_auto_enabled: dict[str, frozenset[str]],
    enabled: bool = False,
) -> APIRouter:
    """Assemble the inbound router.

    `channels`: channel name → adapter. This mapping is the ONLY place platform names live.
    `endpoint_to_shop`: `(channel, external_id)` → shop_id. Temporary in-memory map; a
    `shops` table lookup lands with Spec 03 Phase 1.
    `shop_auto_enabled`: per-shop opt-in intent sets — an unconfigured shop defaults to an
    empty set, so it always parks rather than auto-sending.
    `enabled=False` returns 503 on every request.
    """

    router = APIRouter(prefix="/webhook", tags=["webhook"])

    @router.post("/{channel}/{external_id}")
    async def inbound(
        channel: str,
        external_id: str,
        req: Request,
        payload: dict[str, Any] = Body(...),
    ) -> dict[str, object]:
        if not enabled:
            raise HTTPException(status_code=503, detail="webhook_disabled")

        adapter = channels.get(channel)
        if adapter is None:
            raise HTTPException(status_code=404, detail="unknown_channel")

        shop_id = endpoint_to_shop.get((channel, external_id))
        if shop_id is None:
            # Same shape as "unknown channel" — do not leak which endpoints are registered.
            raise HTTPException(status_code=404, detail="unknown_endpoint")

        # TODO(PRE-004): verify platform signature over the RAW body BEFORE parsing.
        _ = req  # kept for the signature-verify pass — do not remove.

        try:
            msg = adapter.parse_inbound(payload)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="unparsable_payload") from exc

        # External identity → our identity. This is what removed the orchestrator's old
        # `conversation_id or customer_id` shim: real rows exist before the draft is parked.
        async with session_factory() as session:
            customer_id, conversation_id = await resolve_conversation(
                session,
                shop_id=shop_id,
                channel=channel,
                external_user_id=msg.external_user_id,
                external_thread_id=msg.external_thread_id,
            )

            # Ghi tin khách NGAY tại đây — trước `receive_and_draft` (spec 10 H1).
            # Thứ tự là có chủ ý: drafter/LLM nổ thì tin khách vẫn nằm trong log. Mất tin
            # khách không phục hồi được (Zalo không cho đọc lại lịch sử); mất draft thì
            # retry được. `shop_id` không truyền vào repo — nó baked từ `shop_scope`, nên
            # kể cả `endpoint_to_shop` map sai cũng không ghi lệch sang shop khác được.
            # ⚠️ KHÔNG idempotent: Zalo retry cùng payload ⇒ 2 row. Đã biết và đã chấp nhận
            # (H1 GOAL-AMEND) — dedup là `webhook_event_log`, spec 03 Phase 2, BLOCKED.
            await MessageRepo(session, shop_scope=shop_id).append(
                conversation_id=conversation_id,
                customer_id=customer_id,
                role="user",
                content=msg.text,
            )

        outcome: ReceiveOutcome = await receive_and_draft(
            shop_id=shop_id,
            customer_id=customer_id,
            conversation_id=conversation_id,
            message=msg.text,
            drafter=drafter,
            sender=adapter,
            session_factory=session_factory,
            shop_auto_enabled_intents=shop_auto_enabled.get(shop_id, frozenset()),
        )
        return {
            "action": outcome.action,
            "reason": outcome.reason,
            "reply_id": outcome.reply_id,
        }

    return router
