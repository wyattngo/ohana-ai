"""Zalo channel adapter (spec 06 Phase F1).

Wraps the EXISTING `bridge/zalo_sender.py` rather than replacing it: `ZaloSender`'s
signature is a contract Spec 03c depends on when it swaps `MockZaloSender` for the real
HTTP sender. This adapter adds the channel seam without touching that file.

The inbound payload shape below is the GĐ0 placeholder — the same `{customer_id, message}`
the pre-F1 webhook accepted. PRE-004 brings Zalo's real webhook envelope; when it lands,
only `parse_inbound` changes, because the core no longer knows what a Zalo payload is.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from bridge.zalo_sender import ZaloSender
from channels.base import InboundMessage


class ZaloChannel:
    name = "zalo"

    def __init__(self, *, sender: ZaloSender) -> None:
        self._sender = sender

    def parse_inbound(self, payload: Mapping[str, Any]) -> InboundMessage:
        # PRE-004 placeholder envelope. Missing sender id is fatal, never defaulted — a
        # message attributed to the wrong customer is worse than a rejected webhook.
        external_user_id = payload.get("customer_id")
        text = payload.get("message")
        if not isinstance(external_user_id, str) or not external_user_id:
            raise ValueError("zalo payload missing 'customer_id'")
        if not isinstance(text, str) or not text:
            raise ValueError("zalo payload missing 'message'")
        return InboundMessage(
            external_user_id=external_user_id,
            text=text,
            external_thread_id=payload.get("thread_id"),
        )

    async def send(self, *, shop_id: str, customer_id: str, text: str) -> None:
        await self._sender.send(shop_id=shop_id, customer_id=customer_id, text=text)
