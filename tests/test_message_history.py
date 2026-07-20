"""H0 gate (spec `10-Task-OhanaAISeller-ConversationHistory.md` §7 Phase H0).

Viết TRƯỚC khi `Message` có `conversation_id`/`customer_id`/FK ⇒ expected RED.

**Vì sao `Message` là bảng duy nhất trong repo không có FK.** Spec 06 F0 gắn composite FK
`(shop_id, X) → parent(shop_id, id)` cho `Conversation`, `OrderDraft`, `PendingReply` —
và bỏ sót `Message`. Hệ quả không phải thẩm mỹ: bảng không biết message thuộc conversation
nào, nên câu "load last-N của conversation này" KHÔNG viết được. Cùng lắm lọc theo `shop_id`,
tức trộn chung mọi khách của một shop.

**Vì sao FK phải COMPOSITE, và vì sao test phải chứng minh bằng `IntegrityError`.**
`FOREIGN KEY (conversation_id) → conversations(id)` chỉ khẳng định "conversation này tồn
tại". Nó cho phép message của shop A trỏ conversation của shop B và Postgres vui vẻ nhận —
đúng lỗ R1.22. Chỉ dạng composite mới ghim row được tham chiếu vào CÙNG shop. Một test chỉ
hỏi "FK có tồn tại không" sẽ XANH với cả hai dạng, tức không phân biệt được bản vá thật với
bản vá giả. Nên `test_cross_shop_message_rejected_by_database` mới là bằng chứng, phần còn
lại là canh đường.

**Giới hạn đã biết của các test ở đây — đọc trước khi tin chúng quá mức.** `fresh_db` dựng
schema bằng `Base.metadata.create_all`, KHÔNG qua Alembic (xem docstring `conftest.py`).
Nghĩa là mọi assertion dưới đây kiểm **model**, không kiểm **migration**. Model đúng mà
`0006` viết sai thì suite này vẫn xanh. Tính đúng của migration có gate riêng và phải chạy
thật: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` trong GATE_FULL.
Đừng gộp hai thứ đó làm một.
"""

from __future__ import annotations

import uuid

import pytest
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError

_FK_CONVERSATION = "fk_messages_conversation_same_shop"
_FK_CUSTOMER = "fk_messages_customer_same_shop"
_INDEX = "idx_msg_shop_conv_created"


def _uid(p: str) -> str:
    return f"{p}_{uuid.uuid4().hex[:12]}"


async def _seed_shop(conn: sa.ext.asyncio.AsyncConnection, shop: str) -> tuple[str, str]:
    """Tạo (customer, conversation) hợp lệ cho `shop`. Trả `(customer_id, conversation_id)`."""
    cus, conv = _uid("cus"), _uid("conv")
    await conn.execute(
        sa.text(
            "insert into customers (id, shop_id, channel, external_id) values (:i, :s, 'zalo', :e)"
        ),
        {"i": cus, "s": shop, "e": _uid("ext")},
    )
    await conn.execute(
        sa.text(
            "insert into conversations (id, shop_id, customer_id, channel) "
            "values (:i, :s, :c, 'zalo')"
        ),
        {"i": conv, "s": shop, "c": cus},
    )
    return cus, conv


# --- (a) cột tồn tại và NOT NULL -----------------------------------------------------


@pytest.mark.asyncio
async def test_message_has_conversation_and_customer_columns(fresh_db) -> None:
    """(a) Hỏi `information_schema`, không tin khai báo trong Python.

    NOT NULL là phần có ý nghĩa: cột nullable sẽ cho phép message mồ côi lọt vào, và
    lịch sử thủng một cách âm thầm đúng như ISSUE-020 — cột có trong schema, không ai ghi.
    """
    engine, _ = await fresh_db()
    async with engine.connect() as c:
        rows = (
            await c.execute(
                sa.text(
                    "select column_name, is_nullable from information_schema.columns "
                    "where table_name = 'messages'"
                )
            )
        ).all()
    cols = {r[0]: r[1] for r in rows}

    assert "conversation_id" in cols, f"`messages` thiếu conversation_id — có: {sorted(cols)}"
    assert "customer_id" in cols, f"`messages` thiếu customer_id — có: {sorted(cols)}"
    assert cols["conversation_id"] == "NO", "conversation_id phải NOT NULL"
    assert cols["customer_id"] == "NO", "customer_id phải NOT NULL"


# --- (b) FK là COMPOSITE, không phải FK đơn ------------------------------------------


@pytest.mark.asyncio
async def test_foreign_keys_are_composite_on_shop_id(fresh_db) -> None:
    """(b) Đọc `pg_constraint` và kiểm ĐÚNG cặp cột, không chỉ kiểm tên FK tồn tại.

    Một FK tên đúng nhưng chỉ trên `conversation_id` sẽ qua được bài kiểm "có tồn tại
    không" trong khi không chặn gì cross-tenant. Nên assertion nằm ở DANH SÁCH CỘT.
    """
    engine, _ = await fresh_db()
    async with engine.connect() as c:
        rows = (
            await c.execute(
                sa.text("""
                select con.conname, array_agg(att.attname order by k.ord) as cols
                from pg_constraint con
                join pg_class rel on rel.oid = con.conrelid
                join lateral unnest(con.conkey) with ordinality as k(attnum, ord) on true
                join pg_attribute att
                  on att.attrelid = con.conrelid and att.attnum = k.attnum
                where rel.relname = 'messages' and con.contype = 'f'
                group by con.conname
                """)
            )
        ).all()
    fks = {r[0]: list(r[1]) for r in rows}

    assert _FK_CONVERSATION in fks, f"thiếu {_FK_CONVERSATION} — FK hiện có: {sorted(fks)}"
    assert _FK_CUSTOMER in fks, f"thiếu {_FK_CUSTOMER} — FK hiện có: {sorted(fks)}"
    assert fks[_FK_CONVERSATION] == ["shop_id", "conversation_id"], (
        f"FK conversation phải COMPOSITE trên (shop_id, conversation_id), "
        f"đang là {fks[_FK_CONVERSATION]} — FK đơn KHÔNG chặn cross-tenant"
    )
    assert fks[_FK_CUSTOMER] == ["shop_id", "customer_id"], (
        f"FK customer phải COMPOSITE trên (shop_id, customer_id), đang là {fks[_FK_CUSTOMER]}"
    )


# --- (c) bằng chứng thật: Postgres TỪ CHỐI cross-shop --------------------------------


@pytest.mark.asyncio
async def test_cross_shop_message_rejected_by_database(fresh_db) -> None:
    """(c) **Đây là bằng chứng, không phải (a)/(b).**

    Dựng conversation hợp lệ ở shop B, rồi thử ghi message khai `shop_id='A'` trỏ vào nó.
    Với FK đơn, Postgres nhận (conversation TỒN TẠI). Với FK composite, Postgres từ chối
    (cặp `(A, conv_của_B)` không có trong `conversations(shop_id, id)`).

    Đây đúng là bài kiểm mà `test_cross_shop_reference_rejected_by_database` của spec 06 F0
    đã làm cho `Conversation` — `Message` chưa từng có bản tương ứng.
    """
    engine, _ = await fresh_db()
    shop_a, shop_b = _uid("shopA"), _uid("shopB")
    async with engine.begin() as c:
        cus_a, _ = await _seed_shop(c, shop_a)
        _, conv_b = await _seed_shop(c, shop_b)

    with pytest.raises(IntegrityError):
        async with engine.begin() as c:
            await c.execute(
                sa.text(
                    "insert into messages (shop_id, role, content, conversation_id, customer_id) "
                    "values (:s, 'user', 'xin chào', :conv, :cus)"
                ),
                # shop A + conversation của shop B = cặp không tồn tại ⇒ phải bị từ chối.
                {"s": shop_a, "conv": conv_b, "cus": cus_a},
            )


@pytest.mark.asyncio
async def test_same_shop_message_accepted(fresh_db) -> None:
    """(c-đối chứng) Cùng shop thì PHẢI ghi được.

    Không có test này thì một FK viết sai tới mức chặn cả ghi hợp lệ vẫn làm test (c) xanh —
    "từ chối mọi thứ" cũng thoả `pytest.raises`. Cặp chấp-nhận/từ-chối mới định nghĩa đúng
    hành vi.
    """
    engine, _ = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        cus, conv = await _seed_shop(c, shop)
        await c.execute(
            sa.text(
                "insert into messages (shop_id, role, content, conversation_id, customer_id) "
                "values (:s, 'user', 'còn size M không', :conv, :cus)"
            ),
            {"s": shop, "conv": conv, "cus": cus},
        )
    async with engine.connect() as c:
        n = (
            await c.execute(
                sa.text("select count(*) from messages where shop_id = :s"), {"s": shop}
            )
        ).scalar_one()
    assert n == 1


# --- (d) index cho đường đọc history -------------------------------------------------


@pytest.mark.asyncio
async def test_history_index_exists(fresh_db) -> None:
    """(d) Index `(shop_id, conversation_id, created_at)` — đường đọc của H2.

    Index cũ `idx_msg_shop_created` phục vụ truy vấn theo shop; nó KHÔNG phục vụ
    "last-N của conversation này". Giữ cả hai, không thay thế.
    """
    engine, _ = await fresh_db()
    async with engine.connect() as c:
        names = {
            r[0]
            for r in (
                await c.execute(
                    sa.text("select indexname from pg_indexes where tablename = 'messages'")
                )
            ).all()
        }
    assert _INDEX in names, f"thiếu index {_INDEX} — hiện có: {sorted(names)}"
    assert "idx_msg_shop_created" in names, "index cũ bị xoá — phải GIỮ, không thay thế"
