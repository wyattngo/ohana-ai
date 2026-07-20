"""S0 gate (spec `11-Task-OhanaAISeller-ShopsPersona.md` §7 Phase S0).

Viết TRƯỚC `Shop`/`ShopProfile`/`ShopKnowledge`/`ShopProfileRepo` ⇒ expected RED.

**Vì sao spec này tồn tại.** `shop_id` là `Text` trần ở mọi bảng và không FK về đâu — nghĩa
là một JWT hợp lệ mang `shop_id` là chuỗi BẤT KỲ và mọi tầng dưới đều tin. Composite FK của
spec 06/10 chặn được row shop A trỏ row shop B, nhưng KHÔNG chặn được một shop chưa từng tồn
tại, vì chưa có bảng cha nào để tham chiếu. S0 dựng bảng cha đó.

**Ba bất biến các test dưới đây bảo vệ, và vì sao mỗi cái đáng một test riêng:**

1. `knowledge` JSONB validate lúc **GHI**, không phải lúc ĐỌC. Validate lúc đọc là hoãn lỗi
   tới thời điểm đắt nhất: `lookup_size` nổ ở production, trên dữ liệu một shop thật, giữa
   cuộc trò chuyện với khách. Chặn ở đường ghi thì người sai là người sửa, ngay lúc sai.
2. Cap persona ở **cả hai tầng** — Pydantic cho thông báo lỗi tử tế, CHECK constraint cho
   thứ không ai bypass được. Pydantic bị bỏ qua bởi raw SQL; CHECK thì không.
3. Đọc cross-shop trả **None**, không raise. Raise phân biệt được "không tồn tại" với "tồn
   tại nhưng của shop khác" — tức rò rỉ chính sự TỒN TẠI của dữ liệu shop khác. Cùng hình
   dạng với `PendingReplyRepo.get`.

**Giới hạn đã biết:** `fresh_db` dựng schema bằng `Base.metadata.create_all`, KHÔNG qua
Alembic (xem `conftest.py`). Mọi assertion ở đây kiểm **model**, không kiểm **migration**.
Migration `0007` có gate riêng và phải chạy thật trên Postgres:
`alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
"""

from __future__ import annotations

import uuid

import pytest
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError

from agent.persona import PERSONA_MAX_CHARS
from db.models import ShopKnowledge
from db.repos import ShopProfileRepo


def _uid(p: str) -> str:
    return f"{p}_{uuid.uuid4().hex[:12]}"


async def _seed_shop(conn: sa.ext.asyncio.AsyncConnection, shop_id: str) -> str:
    await conn.execute(
        sa.text("insert into shops (id, name, status) values (:i, :n, 'active')"),
        {"i": shop_id, "n": f"Shop {shop_id}"},
    )
    return shop_id


# --- (a) bảng cha tồn tại, và FK thật sự bắt buộc ------------------------------------


@pytest.mark.asyncio
async def test_profile_requires_existing_shop(fresh_db) -> None:
    """(a) Profile trỏ shop KHÔNG tồn tại ⇒ Postgres TỪ CHỐI.

    Đây là điều spec 11 sinh ra để làm: trước nó, `shop_id` không có bảng cha nên không có
    cách nào phân biệt một shop thật với một chuỗi ai đó tự khai.
    """
    engine, _ = await fresh_db()
    with pytest.raises(IntegrityError):
        async with engine.begin() as c:
            await c.execute(
                sa.text(
                    "insert into shop_profile (shop_id, persona_md, knowledge) "
                    "values (:s, 'xin chào', '{}'::jsonb)"
                ),
                {"s": _uid("shop_khong_ton_tai")},
            )


@pytest.mark.asyncio
async def test_profile_accepted_for_existing_shop(fresh_db) -> None:
    """(a-đối chứng) Shop có thật thì PHẢI ghi được.

    Thiếu test này thì một FK viết sai tới mức chặn cả ghi hợp lệ vẫn làm test trên xanh —
    "từ chối mọi thứ" cũng thoả `pytest.raises`.
    """
    engine, _ = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)
        await c.execute(
            sa.text(
                "insert into shop_profile (shop_id, persona_md, knowledge) "
                "values (:s, 'Shop thời trang nữ, giọng thân thiện', '{}'::jsonb)"
            ),
            {"s": shop},
        )
    async with engine.connect() as c:
        n = (
            await c.execute(
                sa.text("select count(*) from shop_profile where shop_id = :s"), {"s": shop}
            )
        ).scalar_one()
    assert n == 1


@pytest.mark.asyncio
async def test_one_profile_per_shop(fresh_db) -> None:
    """(a-bis) `shop_id` là PK của `shop_profile` ⇒ đúng MỘT profile mỗi shop.

    Nếu cần versioning về sau thì đó là bảng khác, KHÔNG phải nới PK này — hai profile
    "đang hoạt động" cho một shop nghĩa là không ai biết AI đang nói bằng giọng nào.
    """
    engine, _ = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)
        await c.execute(
            sa.text(
                "insert into shop_profile (shop_id, persona_md, knowledge) "
                "values (:s, 'bản 1', '{}'::jsonb)"
            ),
            {"s": shop},
        )
    with pytest.raises(IntegrityError):
        async with engine.begin() as c:
            await c.execute(
                sa.text(
                    "insert into shop_profile (shop_id, persona_md, knowledge) "
                    "values (:s, 'bản 2', '{}'::jsonb)"
                ),
                {"s": shop},
            )


# --- (b) knowledge JSONB validate lúc GHI --------------------------------------------


def test_knowledge_rejects_unknown_field() -> None:
    """(b) Field lạ bị TỪ CHỐI, không bị bỏ qua im lặng.

    `extra="forbid"` chứ không phải mặc định: nếu seller gõ nhầm `size_charts` (thừa `s`)
    mà model lặng lẽ bỏ qua, họ sẽ thấy "lưu thành công" rồi `lookup_size` trả `not_found`
    mãi mãi, và không có gì trên màn hình giải thích vì sao.
    """
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        ShopKnowledge.model_validate({"size_charts": []})


def test_knowledge_rejects_wrong_shape() -> None:
    """(b) Shape sai bị chặn — đây là loại lỗi chỉ lộ ở production nếu không chặn lúc ghi."""
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        ShopKnowledge.model_validate({"size_chart": [{"size": "M", "height_min_cm": "cao"}]})


@pytest.mark.asyncio
async def test_repo_rejects_invalid_knowledge_at_write(fresh_db) -> None:
    """(b) Chặn ở tầng REPO, không phải tầng API.

    Đặt validate ở repo nghĩa là MỌI đường ghi đều đi qua nó — API, script seed, test,
    migration data-fix. Đặt ở API thì mọi đường khác đều là lỗ.
    """
    from pydantic import ValidationError

    engine, sf = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)

    async with sf() as s:
        repo = ShopProfileRepo(s, shop_scope=shop)
        with pytest.raises((ValidationError, ValueError)):
            await repo.upsert(persona_md="ok", knowledge={"size_chart": [{"size": 123}]})


# --- (c) cap persona: hai tầng, vì chúng hỏng khác nhau ------------------------------


@pytest.mark.asyncio
async def test_persona_over_cap_rejected_by_repo(fresh_db) -> None:
    """(c) Tầng 1 — repo từ chối, thông báo lỗi đọc được."""
    engine, sf = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)

    async with sf() as s:
        repo = ShopProfileRepo(s, shop_scope=shop)
        with pytest.raises(ValueError):
            await repo.upsert(persona_md="x" * (PERSONA_MAX_CHARS + 1), knowledge={})


@pytest.mark.asyncio
async def test_persona_over_cap_rejected_by_database(fresh_db) -> None:
    """(c) Tầng 2 — CHECK constraint, thứ raw SQL không lách được.

    Đây KHÔNG phải test thừa của cái trên. Chúng bảo vệ hai đường khác nhau: Pydantic/repo
    bảo vệ đường ứng dụng, CHECK bảo vệ mọi đường còn lại (psql tay, script, data-fix).
    Ngân sách token là ràng buộc chung của hệ thống — nó không nên phụ thuộc vào việc
    người ghi có nhớ dùng repo hay không.
    """
    engine, _ = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)

    with pytest.raises(IntegrityError):
        async with engine.begin() as c:
            await c.execute(
                sa.text(
                    "insert into shop_profile (shop_id, persona_md, knowledge) "
                    "values (:s, :p, '{}'::jsonb)"
                ),
                {"s": shop, "p": "x" * (PERSONA_MAX_CHARS + 1)},
            )


# --- (d) đọc cross-shop trả None, KHÔNG raise ----------------------------------------


@pytest.mark.asyncio
async def test_cross_shop_profile_read_returns_none(fresh_db) -> None:
    """(d) Shop A đọc profile shop B ⇒ **None**, không raise.

    Raise sẽ phân biệt được "không tồn tại" với "tồn tại nhưng của shop khác" — và chính
    sự phân biệt đó rò rỉ thông tin về shop khác. Cùng hình dạng `PendingReplyRepo.get`.
    """
    engine, sf = await fresh_db()
    shop_a, shop_b = _uid("shopA"), _uid("shopB")
    async with engine.begin() as c:
        await _seed_shop(c, shop_a)
        await _seed_shop(c, shop_b)

    async with sf() as s:
        await ShopProfileRepo(s, shop_scope=shop_b).upsert(
            persona_md="giọng của shop B", knowledge={}
        )

    async with sf() as s:
        assert await ShopProfileRepo(s, shop_scope=shop_a).get() is None
        got = await ShopProfileRepo(s, shop_scope=shop_b).get()
        assert got is not None and got.persona_md == "giọng của shop B"


@pytest.mark.asyncio
async def test_upsert_cannot_write_to_another_shop(fresh_db) -> None:
    """(d-bis) `shop_id` BAKED từ `shop_scope` — repo không nhận nó làm tham số.

    Không có tham số để bẻ thì caller sai cũng không ghi lệch shop được. Test đọc CHỮ KÝ
    hàm chứ không tin docstring: một `shop_id=` lọt vào signature là hồi quy thật.
    """
    import inspect

    params = inspect.signature(ShopProfileRepo.upsert).parameters
    assert "shop_id" not in params, (
        f"`upsert` KHÔNG được nhận shop_id — nó phải baked từ shop_scope. Params: {list(params)}"
    )


@pytest.mark.asyncio
async def test_published_at_defaults_null(fresh_db) -> None:
    """(e) `published_at` mặc định NULL = chưa phát hành (PRE-1102, Wyatt ký).

    Cố ý KHÔNG có `profile_status`/`approved_by`: không có người duyệt thứ hai nào tồn tại,
    nên một cột tên "approved" sẽ mô tả một quy trình không có thật — và về sau sẽ có người
    đọc nó như bằng chứng đã qua kiểm duyệt.
    """
    engine, sf = await fresh_db()
    shop = _uid("shop")
    async with engine.begin() as c:
        await _seed_shop(c, shop)
    async with sf() as s:
        await ShopProfileRepo(s, shop_scope=shop).upsert(persona_md="draft", knowledge={})
        got = await ShopProfileRepo(s, shop_scope=shop).get()
    assert got is not None and got.published_at is None
