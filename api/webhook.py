"""Zalo OA inbound webhook scaffold (spec 01 §3 Sub-task E, step 17).

PRE-004 unresolved — this scaffold accepts a path-scoped `oa_id` (per-shop URL that our
Zalo gateway configures) and a JSON body carrying the inbound message. When PRE-004 lands:

  1. Verify the Zalo signature (HMAC over the raw body with the OA's shared secret).
  2. Look up `oa_id -> shop_id` in a shops table (currently a stub `_oa_to_shop`).
  3. Enforce the 8-msg / 48-hour reactive window per shop.

Until then this endpoint is disabled by default in prod (see the guard in `build_router`)
so an unauthenticated `POST /webhook/zalo/{oa_id}` cannot enqueue a draft. Tests build the
router with `enabled=True`; the gate for phase 5 does NOT exercise this HTTP surface (the
orchestrator is tested directly).

`shop_id` is DERIVED from `oa_id` via lookup — the request body is untrusted and MUST NOT
supply a shop_id claim (R1.1 extended).
"""

from __future__ import annotations

from typing import Protocol

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent.orchestrator import ReceiveOutcome, receive_and_draft
from bridge.zalo_sender import ZaloSender


class _Drafter(Protocol):
    async def draft(self, *, shop_id: str, customer_id: str, message: str): ...  # type: ignore[no-untyped-def]  # returns _Draft


class ZaloInboundBody(BaseModel):
    customer_id: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)


def build_router(
    drafter: _Drafter,
    sender: ZaloSender,
    session_factory: async_sessionmaker[AsyncSession],
    *,
    oa_to_shop: dict[str, str],
    shop_auto_enabled: dict[str, frozenset[str]],
    enabled: bool = False,
) -> APIRouter:
    """Assemble the webhook router.

    `oa_to_shop`: temporary in-memory map — a `shops` table lookup lands with the wider
    schema. `shop_auto_enabled`: per-shop opt-in intent sets (defaults to empty frozenset
    when a shop hasn't been configured, so an unrecognized shop always parks).
    `enabled=False` returns 503 on every request — a defensive default so a misconfigured
    prod deploy can't accept webhooks before PRE-004 clears.
    """

    router = APIRouter(prefix="/webhook", tags=["webhook"])

    @router.post("/zalo/{oa_id}")
    async def zalo_inbound(oa_id: str, req: Request, body: ZaloInboundBody) -> dict[str, object]:
        if not enabled:
            raise HTTPException(status_code=503, detail="zalo_webhook_disabled")

        shop_id = oa_to_shop.get(oa_id)
        if shop_id is None:
            # Unknown OA — same shape as a 404 rather than 4xx that would leak which OAs
            # are registered.
            raise HTTPException(status_code=404, detail="unknown_oa")

        # TODO(PRE-004): verify Zalo signature over raw request body BEFORE reading json.
        _ = req  # kept for future signature-verify pass — do not remove.

        outcome: ReceiveOutcome = await receive_and_draft(
            shop_id=shop_id,
            customer_id=body.customer_id,
            message=body.message,
            drafter=drafter,
            sender=sender,
            session_factory=session_factory,
            shop_auto_enabled_intents=shop_auto_enabled.get(shop_id, frozenset()),
        )
        return {
            "action": outcome.action,
            "reason": outcome.reason,
            "reply_id": outcome.reply_id,
        }

    return router
