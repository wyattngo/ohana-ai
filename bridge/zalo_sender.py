"""Outbound Zalo OA sender — STUB (PRE-004 unresolved).

Spec 01 §6 fallback: "STOP F3 send-leg — build draft engine + inbox UI với mock sender
trước." This module ships a `ZaloSender` Protocol and a `MockZaloSender` that records
sends without any network. The real HTTP sender lands when PRE-004 clears:
  - Zalo OA access token (per-shop) + refresh flow
  - Webhook signature verification (inbound)
  - 8-msg / 48-hour reactive-window enforcement (rate-limit warning surface)

Anything that DOES land here later must keep `verify=True` hardcoded (R1.3) and NEVER
accept `shop_id` from a request body — the sender must be constructed against a shop
context that came from `auth.identity.Identity`.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Protocol

logger = logging.getLogger(__name__)


class ZaloSender(Protocol):
    async def send(self, *, shop_id: str, customer_id: str, text: str) -> None: ...


@dataclass
class MockZaloSender:
    """GĐ0 default. Records every send in `.sends` and logs at INFO. Zero network I/O.

    Swap for a live `ZaloAPISender` once PRE-004 clears — the interface stays the same
    so orchestrator wiring doesn't change (R6 pair).
    """

    sends: list[dict[str, Any]] = field(default_factory=list)

    async def send(self, *, shop_id: str, customer_id: str, text: str) -> None:
        self.sends.append({"shop_id": shop_id, "customer_id": customer_id, "text": text})
        logger.info(
            "zalo_mock_send shop_id=%s customer_id=%s text_len=%d",
            shop_id,
            customer_id,
            len(text),
        )
