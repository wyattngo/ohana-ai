"""Shop-scoped repositories — the ONLY sanctioned access path for tenant-scoped tables.

Every method takes a scope in the constructor (`shop_scope: str`) and every SELECT/UPDATE
statement threads it into a `WHERE shop_id = :scope` clause SQL-level. A caller cannot
build a repo without picking a shop, and one repo instance can only ever surface / mutate
rows for that shop. Ad-hoc `session.execute(select(PendingReply)…)` outside these repos is
a S4 breach.

`ConversationRepo`, `PendingReplyRepo` and `MessageRepo` live here. `Embedding` stays
in-place at the retrieval boundary because that path locks shop scope in a different layer
(`PgvectorRetriever(shop_scope=…)`).

`MessageRepo` landed in spec 10 H1 — the old note here said messages could stay as an
"orchestrator direct-insert with a verified shop_id", which was the wrong seam: it puts
`shop_id` back in the caller's hands at exactly the point where a bug becomes a cross-tenant
write. Baking the scope into the repo removes the parameter a caller could get wrong.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Any, cast

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.engine import CursorResult
from sqlalchemy.ext.asyncio import AsyncSession

from agent.persona import PERSONA_MAX_CHARS
from db.models import (
    Conversation,
    Message,
    PendingReply,
    ShopKnowledge,
    ShopProfile,
    WebhookEventLog,
)

# Khai tường minh thay vì nhận string tuỳ ý: `role` sai chính tả (vd "Assistant") sẽ làm
# `last_n` trả đúng row nhưng LLM đọc sai vai — hỏng âm thầm, không exception nào.
_MESSAGE_ROLES = frozenset({"user", "assistant", "seller", "system"})


class ConversationRepo:
    """Shop-scoped access to `conversations` (spec 06 Phase F0).

    Same seam as PendingReplyRepo: scope is chosen at construction, every statement carries
    `WHERE shop_id = :scope`. Note this is belt-AND-braces with the composite FKs in
    db/models.py — the FKs stop a row from being WRITTEN across shops, this repo stops rows
    from being READ across shops. Neither replaces the other.
    """

    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def list_recent(self, *, limit: int = 50) -> Sequence[Conversation]:
        """Most-recent-first threads for THIS shop."""
        stmt = (
            select(Conversation)
            .where(Conversation.shop_id == self._shop_scope)
            .order_by(Conversation.created_at.desc())
            .limit(limit)
        )
        return (await self._session.execute(stmt)).scalars().all()

    async def get(self, conversation_id: str) -> Conversation | None:
        """Fetch one thread by id — scoped. An id owned by another shop returns None
        (same shape as "not found"; we do not distinguish, so the caller cannot probe
        for existence of another shop's rows)."""
        stmt = (
            select(Conversation)
            .where(Conversation.shop_id == self._shop_scope)
            .where(Conversation.id == conversation_id)
        )
        return (await self._session.execute(stmt)).scalar_one_or_none()


class PendingReplyRepo:
    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def create(
        self,
        *,
        reply_id: str,
        conversation_id: str,
        customer_id: str,
        draft_text: str,
        intent: str,
        confidence: float,
        snapshot: dict[str, Any] | None = None,
        expires_at: datetime | None = None,
    ) -> PendingReply:
        """Insert a new parked draft. `shop_id` is baked from the repo scope — the caller
        does NOT pass it, so a compromised caller cannot cause a row to land under a shop
        other than the one this repo was scoped to.

        `snapshot` / `expires_at` are OPTIONAL (spec 14 A0) — the tier-1 T0 snapshot and the
        TTL are captured by deferred runtime; today every call-site omits them and the row
        lands with both NULL. Wiring them is a later phase, but the columns exist now so that
        wiring is an INSERT-shape change, not a data migration on live shop rows."""
        row = PendingReply(
            reply_id=reply_id,
            shop_id=self._shop_scope,
            conversation_id=conversation_id,
            customer_id=customer_id,
            draft_text=draft_text,
            intent=intent,
            confidence=confidence,
            status="pending",
            snapshot=snapshot,
            expires_at=expires_at,
        )
        self._session.add(row)
        await self._session.commit()
        return row

    async def list_pending(self) -> Sequence[PendingReply]:
        """List parked drafts for THIS shop, oldest-first (fair queue for the seller)."""
        stmt = (
            select(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.status == "pending")
            .order_by(PendingReply.created_at)
        )
        return (await self._session.execute(stmt)).scalars().all()

    async def get(self, reply_id: str) -> PendingReply | None:
        """Fetch one parked draft by id — scoped. A reply_id belonging to another shop
        returns None (not a leak, not a raise — same shape as "row not found")."""
        stmt = (
            select(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.reply_id == reply_id)
        )
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def mark_decided(self, reply_id: str, *, new_status: str, decided_by: str) -> int:
        """Transition a parked reply to approved / rejected / sent. Returns the number of
        rows updated — 0 means the reply_id doesn't exist FOR THIS SHOP (either wrong
        shop, or already-decided). The `shop_id` clause is the S4 ownership seam: a shop_b
        seller cannot approve a shop_a draft even if they somehow know the reply_id."""
        if new_status not in {"approved", "rejected", "sent"}:
            raise ValueError(f"invalid status transition: {new_status!r}")
        # `label` = train signal cho auto-send (spec 14 A0, workflow §8.1) — derive TRONG repo
        # từ `new_status`, KHÔNG để caller tự khai (caller khai = chỗ ghi sai nhãn vào training
        # set). CHỈ approve/reject là quyết định của SELLER; `sent` là lifecycle worker gửi,
        # không phải tín hiệu train ⇒ KHÔNG đè label (một reply approved→sent giữ label
        # 'approved'). `edited` là đường ghi riêng khi edit-endpoint land (chưa có).
        values: dict[str, Any] = {
            "status": new_status,
            "decided_by": decided_by,
            "decided_at": datetime.now(UTC),
        }
        if new_status in {"approved", "rejected"}:
            values["label"] = new_status
        stmt = (
            update(PendingReply)
            .where(PendingReply.shop_id == self._shop_scope)
            .where(PendingReply.reply_id == reply_id)
            .where(PendingReply.status.in_(["pending", "approved"]))
            .values(**values)
        )
        # `AsyncSession.execute` is typed as returning `Result`, but a DML statement always
        # yields a `CursorResult` — that is the only variant carrying `rowcount`, and the
        # rowcount is what tells the caller whether the reply belonged to THIS shop.
        result = cast("CursorResult[Any]", await self._session.execute(stmt))
        await self._session.commit()
        return int(result.rowcount or 0)


class MessageRepo:
    """Shop-scoped access to `messages` (spec 10 Phase H1).

    **Append-only log, KHÔNG phải hàng đợi gửi.** Một row ở đây nghĩa là "việc này ĐÃ xảy
    ra", không phải "hãy gửi cái này". Đường duy nhất tới khách hàng đi qua
    `agent/policy_gate.py`; drain bảng này để gửi là bypass gate — nếu bạn đang định viết
    một worker đọc từ đây rồi gọi sender, dừng lại và đọc `agent/orchestrator.py` trước.

    **Idempotency KHÔNG có ở tầng này** (spec 10 H1 GOAL-AMEND, Wyatt ký 2026-07-20).
    `messages` không có khoá dedup, nên gọi `append()` hai lần với cùng nội dung tạo HAI
    row. Đó là hành vi đã biết và đã chấp nhận, không phải thiếu sót: cơ chế chống trùng là
    `webhook_event_log` (`event_id` PRIMARY KEY) thuộc spec 03 Phase 2, đang BLOCKED chờ
    PRE-004. 🚫 Đừng "vá tạm" bằng select-then-insert ở đây — đó đúng là ISSUE-017 mà spec
    09 vừa đóng: hai webhook đồng thời vẫn lọt cả hai, test đơn luồng vẫn xanh, và nó chỉ
    TRÔNG như đã vá. Dedup phải ở tầng DB hoặc không làm.
    """

    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def append(
        self,
        *,
        conversation_id: str,
        customer_id: str,
        role: str,
        content: str,
    ) -> Message:
        """Ghi một message. `shop_id` BAKED từ scope repo — caller KHÔNG truyền.

        Không có tham số `shop_id` nghĩa là không có tham số nào để bẻ: một caller bị lỗi
        hoặc bị chiếm quyền vẫn không ghi được row sang shop khác. Composite FK của H0 là
        lớp thứ hai — Postgres từ chối nếu `(shop_id, conversation_id)` không khớp.
        """
        if role not in _MESSAGE_ROLES:
            raise ValueError(f"invalid role: {role!r} (hợp lệ: {sorted(_MESSAGE_ROLES)})")
        row = Message(
            shop_id=self._shop_scope,
            conversation_id=conversation_id,
            customer_id=customer_id,
            role=role,
            content=content,
        )
        self._session.add(row)
        await self._session.commit()
        return row

    async def last_n(self, conversation_id: str, *, limit: int = 20) -> list[Message]:
        """N message GẦN NHẤT của conversation này, trả theo thứ tự thời gian TĂNG dần.

        Conversation của shop khác trả **rỗng**, KHÔNG raise — raise sẽ phân biệt được
        "không tồn tại" với "tồn tại nhưng của shop khác", tức rò rỉ chính sự TỒN TẠI của
        dữ liệu shop khác. Cùng hình dạng với `PendingReplyRepo.get` trả None.

        Lấy `DESC LIMIT n` rồi đảo lại trong Python: cần n cái MỚI nhất, nhưng LLM cần đọc
        chúng theo thứ tự hội thoại. `ASC LIMIT n` sẽ lấy nhầm n cái CŨ nhất — sai âm thầm,
        và càng dài hội thoại càng sai.
        """
        if limit <= 0:
            raise ValueError(f"limit phải > 0, nhận {limit}")
        stmt = (
            select(Message)
            .where(Message.shop_id == self._shop_scope)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.desc(), Message.id.desc())
            .limit(limit)
        )
        rows = list((await self._session.execute(stmt)).scalars().all())
        rows.reverse()
        return rows


class ShopProfileRepo:
    """Shop-scoped access to `shop_profile` (spec 11 Phase S0).

    **Validate `knowledge` ở ĐÂY, không ở tầng API.** Đặt ở repo nghĩa là MỌI đường ghi đều
    đi qua nó — endpoint admin, script seed, test, data-fix. Đặt ở API thì mọi đường còn lại
    đều là lỗ, và cái lọt qua sẽ không nổ lúc ghi mà nổ lúc `lookup_size` chạy: ở production,
    trên dữ liệu một shop thật, giữa cuộc trò chuyện với khách.

    **Cap `persona_md` kiểm ở đây LẪN ở CHECK constraint.** Không thừa: lớp này cho thông
    báo lỗi người đọc được, CHECK là thứ raw SQL không lách được. Ngân sách token là ràng
    buộc của hệ thống, nó không nên phụ thuộc vào việc người ghi có nhớ dùng repo hay không.
    """

    def __init__(self, session: AsyncSession, *, shop_scope: str) -> None:
        if not shop_scope:
            raise ValueError("shop_scope is required — no default, no cross-tenant surface")
        self._session = session
        self._shop_scope = shop_scope

    async def get(self) -> ShopProfile | None:
        """Profile của THIS shop, hoặc None.

        Profile của shop khác trả **None**, KHÔNG raise — raise sẽ phân biệt được "không
        tồn tại" với "tồn tại nhưng của shop khác", tức rò rỉ chính sự TỒN TẠI của dữ liệu
        shop khác. Cùng hình dạng `PendingReplyRepo.get`.
        """
        stmt = select(ShopProfile).where(ShopProfile.shop_id == self._shop_scope)
        return (await self._session.execute(stmt)).scalar_one_or_none()

    async def upsert(
        self,
        *,
        persona_md: str,
        knowledge: dict[str, Any],
        published_at: datetime | None = None,
    ) -> ShopProfile:
        """Ghi/đè profile. `shop_id` BAKED từ scope repo — caller KHÔNG truyền.

        Không có tham số `shop_id` nghĩa là không có tham số nào để bẻ: caller lỗi hoặc bị
        chiếm quyền vẫn không ghi được sang shop khác. FK về `shops.id` là lớp thứ hai —
        Postgres từ chối nếu shop không tồn tại.

        `knowledge` đi qua `ShopKnowledge.model_validate` (extra="forbid") TRƯỚC khi chạm
        DB. Field lạ bị TỪ CHỐI chứ không bỏ qua im lặng: seller gõ `size_charts` thừa `s`
        mà bị nuốt ⇒ họ thấy "lưu thành công" rồi `lookup_size` trả `not_found` mãi mãi.
        """
        if len(persona_md) > PERSONA_MAX_CHARS:
            raise ValueError(f"persona_md {len(persona_md)} ký tự, vượt cap {PERSONA_MAX_CHARS}")
        # Validate rồi ghi lại dạng đã chuẩn hoá — KHÔNG ghi dict thô của caller.
        validated = ShopKnowledge.model_validate(knowledge)

        row = await self.get()
        if row is None:
            row = ShopProfile(shop_id=self._shop_scope)
            self._session.add(row)
        row.persona_md = persona_md
        row.knowledge = validated.model_dump()
        if published_at is not None:
            row.published_at = published_at
        await self._session.commit()
        return row


class WebhookEventRepo:
    """Idempotency cho inbound webhook (spec 14 B0, workflow §2.1 #2).

    KHÔNG `shop_scope`, KHÁC mọi repo khác trong file này — idempotency là biên giới
    NỀN-TẢNG, không phải dữ liệu tenant. 🚫 Đừng "sửa" thành shop-scoped: `platform_msg_id`
    duy nhất theo channel trên toàn nền tảng, và scope theo shop sẽ cho retry của cùng một
    event (đến trước lúc `shop_id` được suy ra) lọt hai lần.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def record_event(self, *, channel: str, platform_msg_id: str, shop_id: str) -> bool:
        """Ghi một event lần đầu. Trả `True` nếu đây là lần đầu thấy `(channel, platform_msg_id)`,
        `False` nếu đã thấy (retry) — caller dùng `False` để bỏ qua, KHÔNG enqueue lại.

        MỘT câu `INSERT ... ON CONFLICT DO NOTHING RETURNING` — race-safe ở tầng DB. KHÔNG
        select-then-insert: hai webhook đồng thời cùng key sẽ cùng thấy "chưa có" rồi insert
        cả hai (đúng ISSUE-017 mà spec 09 đóng cho Conversation). Ở đây conflict ⇒ RETURNING
        rỗng ⇒ `False`, và Postgres đảm bảo đúng một bên thắng.
        """
        stmt = (
            pg_insert(WebhookEventLog)
            .values(channel=channel, platform_msg_id=platform_msg_id, shop_id=shop_id)
            .on_conflict_do_nothing(index_elements=["channel", "platform_msg_id"])
            .returning(WebhookEventLog.platform_msg_id)
        )
        inserted = (await self._session.execute(stmt)).first()
        await self._session.commit()
        return inserted is not None
