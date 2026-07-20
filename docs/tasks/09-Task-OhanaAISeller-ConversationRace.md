# 09-Task-OhanaAISeller-ConversationRace

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-20 "làm ISSUE-017 luôn") -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng safety→trust→stability→growth. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Unique constraint chặn race tạo trùng `Conversation` (đóng ISSUE-017) |
| Parent | Spec 06 F1 — khai KNOWN UNCOVERED ngay trong docstring `channels/identity.py` |
| Depends-on | Spec 06 (Foundation, DONE) · Spec 08 (lấy migration `0004`, DONE) |
| Unblocks | Spec 03c mount `api/webhook.py` — ISSUE-017 ghi rõ "BẮT BUỘC làm TRƯỚC" |
| Owner | R: Claude · A: Wyatt |
| Branch | `main` (commit thẳng — khớp spec 06/07/08) |
| Spec type | Patch · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

`resolve_conversation()` vá race cho `Customer` nhưng **không** vá cho `Conversation`.

- `Customer`: `pg_insert(...).on_conflict_do_nothing(constraint="uq_customers_shop_chan_ext")` rồi re-select ⇒ race-safe.
- `Conversation`: **select-then-insert**, và bảng `conversations` KHÔNG có unique nào trên `(shop_id, customer_id, channel)`. Hai tin nhắn đến đồng thời từ cùng một khách ⇒ **2 Conversation**.

Hệ quả khi webhook mount: lịch sử hội thoại tách đôi, `PendingReply` gắn vào conversation này còn tin nhắn kế vào conversation kia, AI mất ngữ cảnh. **Không có exception nào** — chỉ là dữ liệu sai âm thầm, cùng họ với prefix bất đối xứng (spec 08) và `_DeterministicDevEmbedder` (spec 04).

**Chưa chảy máu hôm nay:** `api/webhook.py` chưa mount trong `app/main.py`, nên không luồng nào gọi hàm này đồng thời. Đây là lỗi tiềm ẩn có ngày hết hạn rõ ràng — ngày Spec 03c mount webhook.

### Audit on-disk 2026-07-20 — đo, không giả định

1. ✅ `conversations` có `uq_conversations_shop_id (shop_id, id)` + composite FK `(shop_id, customer_id)`. **KHÔNG có** unique trên `(shop_id, customer_id, channel)`. Xác nhận trong `db/models.py` + `0003_foundation_entities.py`.
2. ✅ `conversations` hiện **0 row** (Postgres thật). Migration không có rủi ro dữ liệu trùng.
3. ✅ PG **16.14** local; CI dùng `pgvector/pgvector:pg16` ⇒ `NULLS NOT DISTINCT` (PG15+) **dùng được cả hai nơi**.
4. ⚠️ **`external_thread_id` được nuôi từ đầu tới cuối, không phải cột chết:** `channels/zalo/__init__.py:39` đọc `payload.get("thread_id")` → `channels/base.InboundMessage` → `api/webhook.py:95` → `resolve_conversation()` → cột DB. ISSUE-017 đề xuất `UNIQUE (shop_id, customer_id, channel)` sẽ biến cột này thành trang trí: code vẫn ghi, schema cấm nó có ý nghĩa.
5. ⚠️ **Câu quyết định nằm trong PRE-004 đang BLOCKED:** Zalo có xoay `thread_id` cho cùng một mạch hội thoại không? Không ai biết. Xem §14.

---

## §2 — Goal

**VI:** Postgres TỪ CHỐI conversation trùng ở tầng ràng buộc, chứng minh bằng test chạy đồng thời thật — không phải bằng lý luận. `resolve_conversation()` dùng cùng shape upsert như `Customer`. Đóng ISSUE-017.

**EN:** Postgres rejects duplicate conversations at the constraint layer, proven by a real concurrent test rather than by argument. `resolve_conversation()` uses the same upsert shape as `Customer`. Closes ISSUE-017.

---

## §3 — Scope

- `db/models.py`: `Conversation.__table_args__` += `UniqueConstraint("shop_id", "customer_id", "channel", "external_thread_id", name="uq_conversations_shop_cus_chan_thread", postgresql_nulls_not_distinct=True)`.
- `db/migrations/versions/0005_conversation_unique.py` — thêm constraint. **Không destructive** (bảng 0 row; và kể cả có row, constraint chỉ từ chối cái mới).
- `channels/identity.py`: đổi phần `Conversation` từ select-then-insert sang `pg_insert(...).on_conflict_do_nothing(constraint=...)` + re-select, đối xứng với `Customer`.
- `tests/test_conversation_race.py` (mới).

### Out of scope (cố ý)
- ❌ Mount `api/webhook.py` — đó là Spec 03c, gated PRE-004.
- ❌ Khái niệm đóng/mở lại conversation theo `window_status` — chưa ai định nghĩa, xem §14.
- ❌ Đổi `Customer` — nó đã race-safe.

---

## §4 — Safety Gate Check (trục Ohana)

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Vá đúng một lỗ hỏng-âm-thầm trước khi nó chạm được. Ràng buộc ở tầng DB nên caller sai vẫn bị chặn — không dựa vào code review. | PASS |
| **User trust** | Lịch sử hội thoại không tách đôi ⇒ AI không mất ngữ cảnh giữa chừng. | PASS |
| **Stability** | Bảng 0 row, constraint không destructive, down-migration thật sự reversible (khác `0004`). | PASS |
| **Growth** | Gỡ điều kiện tiên quyết của Spec 03c. | PASS |

**RED FLAG scan:**
- [x] Race → chứng minh bằng test chạy ĐỒNG THỜI thật (2 session song song), không phải bằng đọc code.
- [x] `NULLS NOT DISTINCT` → phải có test riêng: đây là hành vi PG15+ mà nhiều người tưởng là mặc định. Mặc định của SQL là NULL **distinct**, tức không có nó thì constraint KHÔNG chặn được ca thread_id NULL — chính là ca phổ biến nhất hôm nay.
- [x] Down-migration → drop constraint, không mất dữ liệu.

---

## §6 — PRE checks

```
PRE-901: Số migration chưa bị ai lấy — kiểm CẢ trên đĩa LẪN trong spec khác.
  Status: ⚠️ VA CHẠM (lần thứ HAI của cùng một loại). Spec 03 §Files giữ chỗ `0005`.
          Spec 09 land TRƯỚC (spec 03 đang BLOCKED chờ Tân) ⇒ spec 09 lấy `0005`,
          spec 03 dịch sang 0006/0007/0008. Luật: số cấp theo THỨ TỰ LAND.
          → Sửa spec 03 trong cùng phase này.

PRE-902: `conversations` bao nhiêu row (constraint có bị dữ liệu cũ chặn không)?
  Status: ✅ 0 row (đo trên Postgres thật 2026-07-20).

PRE-903: PG có hỗ trợ NULLS NOT DISTINCT không (local VÀ CI)?
  Status: ✅ local 16.14 · CI `pgvector/pgvector:pg16`. PG15+ ⇒ OK cả hai.

PRE-904: Hình dạng constraint — Wyatt chốt.
  Status: ✅ WYATT KÝ 2026-07-20 — phương án **B**:
          UNIQUE (shop_id, customer_id, channel, external_thread_id) NULLS NOT DISTINCT.
          Lý do chọn B thay vì A (§14).
```

---

## §7 — Execute Steps

### Phase C0 — Unique constraint + upsert đối xứng
<!-- ADP:PHASE C0 -->
STATUS: DONE
EVIDENCE: commit=20299d9, gate_exit=0, duration=9s, review=PASS(judge=APPROVE,model=unknown,bound=9c77a82c75cc,tier=medium), smoke=PASS(bound=9c77a82c75cc), ran=2026-07-20T08:44
ROADMAP: GD0-FOUNDATION
GOAL: `conversations` có `uq_conversations_shop_cus_chan_thread` với `NULLS NOT DISTINCT`; hai lời gọi `resolve_conversation()` ĐỒNG THỜI cho cùng một khách trả về CÙNG `conversation_id` và để lại ĐÚNG 1 row; `external_thread_id` khác nhau vẫn tạo được conversation riêng; migration up→down→up sạch.
APPROACH: `UniqueConstraint(..., postgresql_nulls_not_distinct=True)` — bắt buộc, vì mặc định SQL coi NULL là distinct nên không có nó thì ca `thread_id=NULL` (ca phổ biến nhất hôm nay) KHÔNG được chặn. `channels/identity.py` đổi sang `pg_insert(Conversation).on_conflict_do_nothing(constraint=...)` rồi re-select — đối xứng hoàn toàn với nhánh `Customer` ngay trên nó, để người đọc sau không phải hỏi "sao hai nhánh khác nhau". Bỏ `order_by(created_at.desc()).limit(1)`: nó tồn tại để chọn giữa nhiều conversation, mà giờ nhiều conversation là điều schema cấm — giữ lại là để dấu vết của một mô hình không còn đúng.
ALLOWED_FILES: db/models.py, db/migrations/versions/, channels/identity.py, tests/test_conversation_race.py, tests/test_embedding_dim.py, docs/tasks/03-Task-GD0-AcceptanceBackfill.md, docs/tasks/09-Task-OhanaAISeller-ConversationRace.md, docs/memory/KNOWN_ISSUES.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_conversation_race.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (floor rule — ALLOWED_FILES giao RISK_PATHS ở `db/migrations`. KHÔNG nâng lên high: constraint không destructive, bảng 0 row, down thật sự reversible — khác `0004` của spec 08.)
BLOCKED_BY: PRE-901 ✅, PRE-902 ✅, PRE-903 ✅, PRE-904 ✅
SMOKE: PASS ref=docs/smokes/09-C0.md
REVIEW: PASS ref=docs/reviews/09-C0-auto-verdict.json
<!-- /ADP -->

1. `tests/test_conversation_race.py` (RED): (a) constraint tồn tại sau migrate, đọc từ `pg_constraint`; (b) **`NULLS NOT DISTINCT` thật sự bật** — insert 2 row cùng `(shop,cus,chan)` với `thread_id=NULL` ⇒ Postgres TỪ CHỐI cái thứ hai (không có flag này thì nó CHO QUA); (c) **race thật**: 2 `resolve_conversation()` chạy đồng thời trên 2 session ⇒ cùng `conversation_id`, đúng 1 row; (d) `thread_id` KHÁC nhau ⇒ 2 conversation, hợp lệ; (e) migration up→down→up sạch.
2. `db/models.py` += `UniqueConstraint(...)`; viết `0005_conversation_unique.py`.
3. `channels/identity.py` → upsert shape; cập nhật docstring (gỡ đoạn KNOWN UNCOVERED — nó đã hết đúng).
4. Sửa spec 03: dịch `0005/0006/0007` → `0006/0007/0008` (PRE-901).
5. Đóng ISSUE-017 trong `KNOWN_ISSUES.md`.
6. **STOP+WAIT** (ANCHOR).

---

## §8 — DB Changes

**Migration `0005_conversation_unique.py` — KHÔNG destructive.**

```sql
ALTER TABLE conversations
  ADD CONSTRAINT uq_conversations_shop_cus_chan_thread
  UNIQUE NULLS NOT DISTINCT (shop_id, customer_id, channel, external_thread_id);
```

`downgrade` = `DROP CONSTRAINT`. **Reversible thật** cả schema lẫn dữ liệu — khác `0004` (spec 08) vốn xoá dữ liệu ở cả hai chiều.

Nếu tương lai chạy trên bảng đã có row trùng, `ALTER` sẽ FAIL ồn ào. Đó là hành vi đúng: nó bắt người vận hành nhìn dữ liệu trùng trước khi quyết gộp — không được im lặng chọn hộ.

---

## §14 — Open questions

- [x] **Hình dạng constraint** — ✅ Wyatt ký **B** (2026-07-20).
  - **A** = `(shop_id, customer_id, channel)`: một conversation mỗi khách mỗi kênh **vĩnh viễn**; `external_thread_id` thành cột chết.
  - **B** = thêm `external_thread_id` + `NULLS NOT DISTINCT` ← **CHỌN**. Hôm nay hành xử **y hệt A** vì `thread_id` luôn NULL ⇒ race được vá như nhau. Chỉ khác khi thread_id thật xuất hiện.
  - **Lý do chọn:** câu quyết định (Zalo có xoay `thread_id` không?) nằm trong PRE-004 đang BLOCKED. Khi phải đoán, chọn cái mà **đoán sai còn sửa được**: B sai ⇒ phân mảnh, gộp lại được. A sai ⇒ gộp nhầm hai mạch, và dữ liệu đã gộp thì KHÔNG tách lại được.
- [x] **Conversation có đóng/mở lại theo `window_status` không?** ✅ **TRẢ LỜI 2026-07-20 — KHÔNG, và không cần ai quyết: ngữ nghĩa đã được chốt sẵn trong spec 03 Phase 10.**
  Phase 10 viết: *"hết window mà chưa reply → notification + **mark conversation expired-window**"*. Tức window hết hạn **đánh dấu** conversation, không tách conversation mới. Đúng ngữ nghĩa Zalo: 48h là cửa sổ **quyền gửi tin**, không phải biên của mạch trò chuyện — khách nhắn lại sau 72h vẫn là cùng một mạch, chỉ là OA mất quyền chủ động nhắn trước.
  ⇒ `window_status` là **thuộc tính của một hội thoại bền**, không phải ranh giới hội thoại. Constraint B **không chặn gì**. Câu hỏi này đóng.
  ⚠️ Nhưng audit để trả lời nó lại lộ ra **ISSUE-020**: `last_inbound_at` và `window_status` **chưa từng được ghi** bởi bất kỳ dòng code nào. Phase 10 query trên `last_inbound_at` sẽ luôn trả rỗng ⇒ seller không bao giờ được cảnh báo, không có lỗi nào. Phải vá trước khi build Phase 10.
- [ ] **PRE-004 về rồi thì rà lại B.** Nếu Zalo xoay `thread_id` giữa mạch, cân nhắc đổi sang A + migration gộp.
