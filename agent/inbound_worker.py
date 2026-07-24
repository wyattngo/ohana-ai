"""Drain durable inbound events into the tenant-scoped conversation log.

This worker is deliberately channel-agnostic. Signature verification and binding lookup live
at the webhook boundary; it only consumes already-trusted outbox rows.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from channels.base import InboundChannel
from channels.identity import resolve_conversation
from db.repos import ConversationRepo, MessageRepo, WebhookOutboxRepo

DEBOUNCE_SECONDS = 4


class InboundWorker:
    def __init__(
        self,
        session_factory: async_sessionmaker[AsyncSession],
        channels: Mapping[str, InboundChannel],
    ) -> None:
        self._session_factory = session_factory
        self._channels = channels

    async def run_once(self, *, limit: int = 100) -> int:
        async with self._session_factory() as session:
            rows = await WebhookOutboxRepo(session).pending(limit=limit)

        processed = 0
        for row in rows:
            adapter = self._channels.get(row.channel)
            if adapter is None:
                continue
            message = adapter.parse_inbound(row.payload)
            async with self._session_factory() as session:
                customer_id, conversation_id = await resolve_conversation(
                    session,
                    shop_id=row.shop_id,
                    channel=row.channel,
                    external_user_id=message.external_user_id,
                    external_thread_id=message.external_thread_id,
                )
            async with self._session_factory() as session:
                inserted = await MessageRepo(session, shop_scope=row.shop_id).append_inbound_once(
                    conversation_id=conversation_id,
                    customer_id=customer_id,
                    content=message.text,
                    channel=row.channel,
                    platform_msg_id=row.platform_msg_id,
                )
            if inserted:
                async with self._session_factory() as session:
                    await ConversationRepo(session, shop_scope=row.shop_id).refresh_debounce(
                        conversation_id,
                        due_at=datetime.now(UTC) + timedelta(seconds=DEBOUNCE_SECONDS),
                    )
            async with self._session_factory() as session:
                await WebhookOutboxRepo(session).mark_delivered(row.id)
            processed += 1
        return processed
