# 06-Task-OhanaAISeller-Foundation

<!-- spec-generator v2.3 · Branch B (raw brief từ Wyatt + P0 audit main-loop 2026-07-18) -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng safety→trust→stability→growth, KHÔNG dùng LR/WP/TV/UR. -->
<!-- ADP:MANIFEST inherited từ ohana-ai/CLAUDE.md §5:
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
-->

## §0 — Header

| Field | Value |
|---|---|
| Title | Foundation — Core data model + Channel abstraction + Test/CI (= "03a" trong PLAN-TechLead) |
| Parent | GĐ0 MVP Wedge (Roadmap v4 §3.0 "🥉 song song, không chờ ai") |
| Depends-on | Spec 01 (5/5 DONE). **KHÔNG** phụ thuộc PRE-002/003/004, **KHÔNG** cần Together key, **KHÔNG** cần ADR PRE-007 ký |
| Unblocks | Spec 03 Phase 5 (credit_ledger FK conversation_id) + Phase 10 (ALTER conversations) — cả hai đang trỏ vào bảng không tồn tại |
| Owner | R: Tân (dev lead) · A: Wyatt (RISK finalize) |
| Branch | `adp/06-foundation` (cắt từ `main`) |
| Duration | 3–5 ngày |
| Spec type | Full · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

Spec 03 (GĐ0 backfill) đứng trên một data-model **không tồn tại**. Audit on-disk 2026-07-18:

**1. Thực thể lõi thương mại vắng mặt hoàn toàn.** `db/models.py` chỉ có `Message`, `Embedding`, `PendingReply`. KHÔNG có `Conversation`, `Customer`, `Order`/`OrderDraft`.

**2. Cột mồ côi đã tồn tại trong code đang chạy.** `PendingReply` khai:
```
conversation_id: Mapped[str] = mapped_column(Text, nullable=False)   # models.py:89
customer_id:     Mapped[str] = mapped_column(Text, nullable=False)   # models.py:90
```
→ code đã *mô hình hoá* conversation + customer như chuỗi trần, không có bảng nào đằng sau. Không FK, không ràng buộc, không thể join.

**3. Hai migration của Spec 03 sẽ FAIL khi apply:**
- `0006` = `ALTER conversations ADD COLUMN last_inbound_at` → **ALTER bảng chưa từng CREATE** (0001 tạo messages+embeddings, 0002 tạo pending_reply — không có `conversations`).
- `0005 credit_ledger` có `conversation_id UUID FK` → trỏ bảng không tồn tại.

**4. TYPE MISMATCH chặn cứng migration 0003/0004/0005.** `shop_id` on-disk là **`Text`** ở cả 3 bảng (models.py:40, 60, 88). Spec 03 §8 lại dự kiến `shops(id UUID)`, `webhook_event_log(shop_id UUID FK)`, `credit_ledger(shop_id UUID FK)`. **FK kiểu UUID không tham chiếu được cột Text** → Postgres từ chối.

**5. Roadmap hứa cái chưa có nền.** GĐ0 milestone + intent taxonomy #9 ("chốt đơn → extraction → draft") gán cho GĐ0, nhưng **không bảng nào chứa order draft**.

**6. Channel hardcode.** Không có `channels/`; `api/webhook.py` import trực tiếp `bridge.zalo_sender.ZaloSender`, route `/webhook/zalo/{oa_id}`. Roadmap §1.1.5 + §5.2.1 yêu cầu land abstraction sớm (refactor tax 3–5× nếu đợi GĐ2) nhưng **không phase nào của Spec 03 làm việc đó**.

**7. Nợ test/CI hẹp (đã đính chính).** CI **đã có** và tốt (`.github/workflows/ci.yml`: service `pgvector/pgvector:pg16` + `redis:7`, ruff check+format, mypy, `alembic upgrade head`, pytest, guardrail). Gap thật chỉ 2 cái: (a) **không có `tests/conftest.py`** (ISSUE-014 OPEN) → mỗi test tự dựng DB; (b) **mypy chỉ chạy `app agent retrieval parsing storage`** (ci.yml:70) → code mới trong `db/` sẽ KHÔNG được type-check.

---

## §2 — Goal

**VI:** Dựng nền móng đang thiếu để Spec 03 chạy được: (a) 3 thực thể lõi `Conversation` / `Customer` / `OrderDraft` tenant-first + Alembic 0003, chốt luôn kiểu identity (Text) và FK cho 2 cột mồ côi của `PendingReply`; (b) `channels/base.py` Protocol + migrate Zalo lên đó để GĐ2 chỉ *thêm* kênh chứ không *mổ* core; (c) `tests/conftest.py` + mở rộng mypy sang `db api auth bridge tools`. Sau spec này, migration 0004/0005/0006 của Spec 03 apply được, và ISSUE-014 đóng.

**EN:** Land the missing foundation Spec 03 stands on: (a) three tenant-first core entities `Conversation` / `Customer` / `OrderDraft` + Alembic 0003, settling the identity type (Text) and FKs for `PendingReply`'s two orphan columns; (b) `channels/base.py` Protocol with Zalo migrated onto it so GĐ2 *adds* a channel instead of *cutting into* core; (c) `tests/conftest.py` + extend mypy to `db api auth bridge tools`. Post-spec, Spec 03's migrations 0004/0005/0006 become applicable and ISSUE-014 closes.

---

## §3 — Scope

### Sub-task A — Core data model (Phase F0)
- `Conversation` (thread khách↔shop), `Customer` (danh tính khách trong 1 shop), `OrderDraft` (đơn AI trích, seller duyệt).
- Mọi bảng: `shop_id Text NOT NULL` + index dẫn đầu bằng `shop_id` (R1.22 analog).
- Alembic `0003` (down_revision = `"0002"`).
- FK hoá 2 cột mồ côi `PendingReply.conversation_id` + `.customer_id`.
- `db/repos.py`: repo mới theo pattern `_shop_scope` (SQL-level `WHERE shop_id = :scope`).
- Files: `db/models.py`, `db/repos.py`, `db/migrations/versions/0003_*.py`, `tests/test_foundation_models.py`.

### Sub-task B — Channel abstraction (Phase F1)
- `channels/base.py`: Protocol `InboundChannel` / `OutboundChannel` (shape tối thiểu, đủ cho Zalo hôm nay + Messenger GĐ2).
- `channels/zalo/`: adapter bọc `bridge/zalo_sender.py` hiện có — **giữ nguyên interface `ZaloSender`** (contract stable, không phá Spec 03c).
- `api/webhook.py`: đổi shape route sang generic `/webhook/{channel}/{external_id}`, resolve adapter qua registry. **VẪN KHÔNG mount** trong `app/main.py` (thiếu concrete `Drafter` — ngoài scope).
- Files: `channels/{__init__,base}.py`, `channels/zalo/{__init__,adapter}.py`, `api/webhook.py`, `bridge/zalo_sender.py` (chỉ nếu cần adapt, ưu tiên KHÔNG đụng), `tests/test_channel_abstraction.py`.

### Sub-task C — Test/CI foundation (Phase F2)
- `tests/conftest.py`: fixture factory DB (dùng `DATABASE_URL`, tương thích service pgvector sẵn có trong CI), fixture tạo/xoá schema per-test hoặc per-session, factory sinh row tenant-scoped.
- `.github/workflows/ci.yml:70`: mở rộng mypy → thêm `db api auth bridge tools`.
- Files: `tests/conftest.py`, `.github/workflows/ci.yml`, `pyproject.toml` (chỉ nếu `[tool.mypy]` xung đột).

### Out of scope (cố ý)
- ❌ Embedder / LLM provider / Together wiring — chờ ADR PRE-007 ký (spec riêng).
- ❌ `shops` table + JWT onboard — đó là Spec 03 Phase 1.
- ❌ Mount `api/webhook.py` — thiếu concrete `Drafter`.
- ❌ `api/inbox.py`, `web/`, `agent/orchestrator.py`, `agent/policy_gate.py`.
- ❌ Migrate `shop_id` Text→UUID (xem PRE-F01 — đề xuất TỪ CHỐI).
- ❌ Order state machine (`draft→paid→shipped…`) — đó là GĐ1 Spec 07; F0 chỉ dựng `OrderDraft` (tiền-trạng-thái).

---

## §4 — Safety Gate Check (Ohana axes — KHÔNG dùng LR/WP/TV/UR)

Priority order: **safety → user trust → stability → growth**.

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | F0 thêm bảng mới + FK; không đổi hành vi tiền/gửi tin. Rủi ro thật = **tenant isolation trên bảng mới** — nếu quên `shop_id` scope SQL-level thì tạo lỗ cross-shop mới (R1.22). Mitigation: gate test cross-shop rejection BẮT BUỘC cho từng bảng mới, repo theo pattern `_shop_scope`. F1 refactor `api/webhook.py` (RISK_PATH) nhưng route **vẫn chưa mount** ⇒ không có đường sống tới khách. | ⚠️ FLAG — gate cross-shop là điều kiện DONE của F0 |
| **User trust** | Không chạm đường reply tới khách. `OrderDraft` là *tiền đề* cho intent #9 nhưng spec này KHÔNG sinh draft, chỉ dựng chỗ chứa. | PASS |
| **Stability** | Đây chính là phase *tăng* stability: vá 2 migration sẽ-fail (0005/0006) + gỡ type-mismatch chặn 0003/0004/0005 + đóng ISSUE-014 + mở mypy sang `db/`. Rủi ro ngược: FK lên `pending_reply` đang có data → xem PRE-F02. | PASS (điều kiện PRE-F02) |
| **Growth** | Không mở scope sản phẩm. Land abstraction sớm để GĐ2 khỏi trả refactor tax 3–5×. | PASS |

**RED FLAG scan:**
- [x] Bảng mới thiếu `shop_id` scope SQL-level → **BLOCK nếu ship**. Mitigation: gate test cross-shop per-table.
- [x] FK lên bảng đang có data production → migration fail hoặc mất data. Mitigation: PRE-F02 verify rỗng + migration có nhánh backfill an toàn.
- [x] Đổi shape route `api/webhook.py` làm vỡ Spec 03c sau này → Mitigation: giữ interface `ZaloSender` nguyên vẹn, contract test.
- [x] Migration không reversible → Mitigation: `downgrade()` thật, test upgrade→downgrade→upgrade.

**VERDICT: PASS (có FLAG).** Ship được. Điều kiện: gate cross-shop cho mọi bảng mới + PRE-F02 xác nhận trước khi FK.

---

## §5 — Source Files & Context (đọc trước khi action)

**Edit-target:**
- `db/models.py` — `Base`, `Message`(:29), `Embedding`(:50), `PendingReply`(:72). `_EMBED_DIM = 1536`(:22). Pattern `shop_id: Mapped[str] = mapped_column(Text, nullable=False)`.
- `db/repos.py` — **chỉ có** `PendingReplyRepo`(:27). Pattern: giữ `self._shop_scope`, mọi query `.where(X.shop_id == self._shop_scope)`.
- `db/migrations/versions/0002_pending_reply.py` — `revision="0002"`, `down_revision="0001"`. → 0003 nối vào đây.
- `api/webhook.py` — scaffold Zalo, `enabled=False` default, chưa mount.
- `.github/workflows/ci.yml:70` — `mypy app agent retrieval parsing storage`.

**Reference (đọc, KHÔNG edit):**
- `docs/tasks/03-Task-GD0-AcceptanceBackfill.md` §8 — DDL dự kiến (0003–0006) mà spec này sẽ sửa kiểu.
- `docs/tasks/PLAN-TechLead-Decomposition-Roadmap.md` — TL-1 (data-model hole), TL-2 (abstraction), TL-9 (đã đính chính).
- `tests/test_tenant_isolation.py` — mẫu adversarial cross-shop hiện có; test mới bám mẫu này.
- `bridge/zalo_sender.py` — interface phải giữ ổn định.

---

## §6 — Pre-flight Checks (binary VERIFY, không phải discovery)

```
PRE-F01: Chốt identity type — Text hay UUID? (Wyatt ký, chặn F0)
  Fact: shop_id = Text NOT NULL ở cả 3 bảng (models.py:40,60,88).
        Spec 03 §8 dự kiến UUID → FK UUID không tham chiếu được Text.
  ĐỀ XUẤT: GIỮ `Text`. Lý do: migrate Text→UUID phải đổi CẢ 3 bảng hiện có
        + JWT claim shop_id + mọi repo + retrieval scope + mọi test —
        rủi ro cao, ZERO lợi ích chức năng ở GĐ0.
  Hệ quả nếu chốt Text: PHẢI sửa Spec 03 §8 DDL (0003/0004/0005) từ UUID → TEXT.
  Expected: Wyatt viết 1 dòng chốt vào §14. If fail: STOP F0.

PRE-F02: pending_reply có data thật không? (chặn bước FK trong F0)
  Command: psql "$DATABASE_URL" -c "SELECT count(*) FROM pending_reply;"
           (chạy trên MỌI env sẽ apply migration: dev + staging nếu có)
  Expected: 0 → FK thẳng, an toàn.
            >0 → migration PHẢI có bước backfill Conversation/Customer từ giá trị
                 conversation_id/customer_id đang có TRƯỚC khi add FK, hoặc FK nullable.
  If fail (không chạy được): STOP, không đoán — FK sai = migration fail lúc deploy.

PRE-F03: alembic head đúng 0002?
  Command: .venv/bin/alembic heads
  Expected: `0002` (single head). Nếu nhiều head → resolve trước, không tạo 0003 chồng.

PRE-F04: spec này KHÔNG bị ADR PRE-007 chặn — xác nhận không chạm provider/region.
  Command: grep -rn "openai\|together\|embed" db/ channels/ tests/conftest.py 2>/dev/null
  Expected: rỗng (không kết quả). Nếu có → scope đã trôi, quay lại §3.
```

---

## §7 — Execute Steps (atomic, one-concern, TDD gate RED trước impl)

### Phase F0 — Core data model + Alembic 0003
<!-- ADP:PHASE F0 -->
STATUS: DONE
EVIDENCE: commit=7f786df, gate_exit=0, duration=4s, review=PASS(judge=APPROVE,model=output-evaluator (haiku) — first-pass auto-verdict,bound=f4bc655d650b,tier=high), ran=2026-07-18T12:58
GOAL: `Conversation` + `Customer` + `OrderDraft` tồn tại, tenant-first (`shop_id Text NOT NULL` + index dẫn đầu `shop_id`); Alembic 0003 apply + downgrade sạch; `PendingReply.conversation_id`/`.customer_id` có FK; test cross-shop rejection PASS trên từng bảng mới; **FK composite (shop_id, …) chặn tham chiếu chéo shop ở tầng DB**.
APPROACH: Thêm 3 model theo đúng pattern `Message`/`PendingReply` (Text id, shop_id Text NOT NULL, created_at server_default now(), Index dẫn đầu shop_id). Identity type = **Text** theo PRE-F01 (KHÔNG UUID — tránh migrate 3 bảng hiện có + JWT + repos). Alembic 0003 `down_revision="0002"`, có `downgrade()` thật. FK cho 2 cột mồ côi theo kết quả PRE-F02 (rỗng → FK thẳng; có data → backfill trước). Repo mới theo pattern `_shop_scope` của `PendingReplyRepo`.
ALLOWED_FILES: db/models.py, db/repos.py, db/migrations/versions/0003_foundation_entities.py, tests/test_foundation_models.py, tests/test_inbox_ui_e2e.py, tests/test_orchestrator.py, docs/reviews/, docs/tasks/06-Task-OhanaAISeller-Foundation.md
GATE: .venv/bin/python -m pytest tests/test_foundation_models.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/alembic upgrade head && .venv/bin/alembic downgrade -1 && .venv/bin/alembic upgrade head
RETRY: 0/3
RISK: high (Wyatt ký 2026-07-18 — giữ nguyên đề xuất; db/models.py + db/migrations trong RISK_PATHS VÀ đổi schema behavior)
REVIEW: PASS ref=docs/reviews/06-F0-auto-verdict.json human=docs/reviews/06-F0-human-review.md
BLOCKED_BY: (đã gỡ) PRE-F01 ✅ TEXT · PRE-F02 ✅ pending_reply 0 rows · PRE-F03 ✅ head=0002
<!-- /ADP -->

1. `tests/test_foundation_models.py` (**RED trước**): (a) tạo Conversation/Customer/OrderDraft shop A; (b) repo scope shop B KHÔNG đọc được row shop A (cross-shop rejection, từng bảng); (c) `shop_id` NOT NULL enforce; (d) FK pending_reply→conversation/customer giữ được ràng buộc. Confirm ĐỎ.
2. Thêm 3 model vào `db/models.py` (KHÔNG đụng `Message`/`Embedding`/`_EMBED_DIM`).
3. Alembic `0003_foundation_entities.py` — create 3 bảng + index; FK lên `pending_reply` theo PRE-F02; `downgrade()` đảo đúng thứ tự.
4. Repo mới trong `db/repos.py` theo pattern `_shop_scope`.
5. Chạy GATE_FULL (gồm upgrade→downgrade→upgrade).
6. **STOP+WAIT** (per-step confirm — RISK high).

**Amendment 2026-07-18 (Wyatt duyệt mở rộng scope).** FK composite làm 6 test cũ vỡ vì chúng
chèn `PendingReply` với `conversation_id`/`customer_id` **bịa** — hành vi mà cột mồ côi cho
phép và FK mới chặn đúng. ALLOWED_FILES mở thêm `tests/test_inbox_ui_e2e.py` +
`tests/test_orchestrator.py` để sửa cho đúng (seed Customer/Conversation cha trước).
GATE_FULL nới thành **toàn suite** — bản cũ chỉ chạy 2 file nên xanh trong khi 6 test khác đỏ;
gate hở kiểu đó nguy hiểm hơn không có gate.

> ⚠️ **KNOWN UNCOVERED (không sửa trong F0 — ngoài ALLOWED_FILES, là RISK_PATH):**
> `agent/orchestrator.py:89` làm `conversation_id=conversation_id or customer_id` — shim có từ
> thời chưa tồn tại bảng `conversations`. Với schema mới, park path sẽ **FK-violate lúc runtime**
> nếu caller không truyền `conversation_id` thật. Hiện CHƯA sống (webhook chưa mount) nên là lỗi
> tiềm ẩn, KHÔNG phải lỗi đang chảy máu — nhưng **bắt buộc sửa trước khi mount webhook** (Spec 03c):
> orchestrator phải resolve/tạo `Conversation` thật thay vì mượn `customer_id`. Đề xuất đưa vào F1.

### Phase F1 — Channel abstraction (Zalo migrate lên Protocol)
<!-- ADP:PHASE F1 -->
STATUS: DONE
EVIDENCE: commit=bbf866b, gate_exit=0, duration=3s, review=PASS(judge=APPROVE,model=output-evaluator (haiku) — first-pass auto-verdict,bound=0fae20e3b664,tier=medium), ran=2026-07-18T13:13
GOAL: `channels/base.py` Protocol tồn tại; Zalo chạy qua adapter thay vì hardcode; `api/webhook.py` dùng shape generic `/webhook/{channel}/{external_id}`; interface `ZaloSender` KHÔNG đổi; **shim `conversation_id or customer_id` ở `agent/orchestrator.py:89` bị GỠ — channel layer resolve Customer/Conversation thật**; toàn bộ test cũ vẫn xanh; webhook VẪN chưa mount.
APPROACH: Protocol tối thiểu đủ cho Zalo hôm nay + Messenger GĐ2 (KHÔNG thiết kế thừa cho kênh chưa thấy — §5.2.4). Adapter `channels/zalo/` bọc `bridge/zalo_sender.py`, KHÔNG sửa file đó. Webhook resolve adapter qua registry theo `{channel}`.
  **Fix shim (Wyatt duyệt gộp vào F1 — 2026-07-18):** identity mapping `(channel, external_user_id) → (customer_id, conversation_id)` đặt ở **channel layer**, vì đó là nơi DUY NHẤT biết id phía kênh. `channels/identity.py resolve_conversation()` upsert Customer+Conversation rồi trả id thật. `agent/orchestrator.py` đổi `conversation_id` thành **tham số BẮT BUỘC** (bỏ hẳn `or customer_id`) — caller luôn biết nó, nên ép ở chữ ký tốt hơn raise lúc chạy.
ALLOWED_FILES: channels/, api/webhook.py, agent/orchestrator.py, tests/test_channel_abstraction.py, tests/test_orchestrator.py, docs/reviews/, docs/tasks/06-Task-OhanaAISeller-Foundation.md
GATE: .venv/bin/python -m pytest tests/test_channel_abstraction.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live'
RETRY: 0/3
RISK: medium (Wyatt ký 2026-07-18, giữ nguyên khi gộp thêm agent/orchestrator.py — refactor behavior-preserving + route chưa mount ⇒ không có đường sống tới khách. 1 confirm tại ANCHOR.)
REVIEW: PASS ref=docs/reviews/06-F1-auto-verdict.json
BLOCKED_BY: (đã gỡ) F0 ✅ DONE — Conversation/Customer đã tồn tại
<!-- /ADP -->

7. `tests/test_channel_abstraction.py` (**RED trước**): (a) adapter Zalo thoả Protocol; (b) webhook resolve đúng adapter theo `{channel}`; (c) channel lạ → 404/400 không crash; (d) interface `ZaloSender` giữ nguyên chữ ký.
8. `channels/base.py` Protocol + `channels/zalo/adapter.py`.
9. `api/webhook.py` đổi sang generic shape + registry. **KHÔNG mount** vào `app/main.py`.
10. Chạy GATE_FULL (toàn suite — đây là refactor, phải chứng minh không vỡ gì).
11. **STOP+WAIT.**

### Phase F2 — Test/CI foundation
<!-- ADP:PHASE F2 -->
STATUS: IN_PROGRESS
GOAL: `tests/conftest.py` cung cấp fixture DB dùng chung (ISSUE-014 đóng); mypy **XANH** trên `app agent retrieval parsing storage db bridge tools`; nợ type còn lại thu gọn đúng `api/`.
APPROACH: conftest dùng `DATABASE_URL` (khớp service pgvector sẵn có trong ci.yml), fixture dựng/dọn schema. 2 test mới của spec này bỏ helper `_fresh_engine`/`_fresh` trùng lặp, chuyển sang fixture chung. **KHÔNG mass-refactor test cũ** — đổi test đang xanh chỉ để "cho đẹp" là rủi ro không được trả công.
  **Amendment 2026-07-18 (Wyatt chọn b2).** Phát hiện khi audit: (a) `mypy` của CI **đã exit=1 trên `main`** trước spec này — 12 lỗi, không do F0/F1; (b) thêm `db bridge tools` vào lệnh mypy là **no-op** vì mypy đã follow-imports vào chúng (đó là lý do `db/repos.py` hiện ra trong CI hiện tại). Nên "mở rộng scope" một mình KHÔNG mua được gì. Thay vào đó sửa đúng 2 lỗi nằm trong scope: `db/repos.py:138` (`Result` vs `CursorResult` — của mình) và `agent/providers/openai_client.py:28` (`app.alert_service` chưa port = **ISSUE-010**, module hiện không import nổi, đã `xfail` trong test → dùng `type: ignore` CÓ ghi rõ ISSUE-010, không phải suppress mù). 10 lỗi còn lại đều ở `api/` (FastAPI `Depends` typing) → **spec riêng**, KHÔNG kéo vào F2.
ALLOWED_FILES: tests/, .github/workflows/ci.yml, pyproject.toml, db/repos.py, agent/providers/openai_client.py, api/inbox.py, api/admin.py, docs/reviews/, docs/tasks/06-Task-OhanaAISeller-Foundation.md
  **Amendment 2 (Wyatt duyệt b2+ — 2026-07-18).** Đính chính của tôi: b2 như khai ban đầu BẤT KHẢ THI — bỏ `api` khỏi *lệnh* mypy không loại nó khỏi *việc kiểm*, vì `app/main.py` import `api/inbox.py` nên follow-imports vẫn kéo vào (đúng cái no-op tôi vừa chỉ ra cho `db bridge tools`, chiều ngược lại). Hoá ra 10 lỗi `api/` là **một root cause**: `identity_dep: object` / `admin_dep: object` khiến mọi `Depends(...)` sai arg-type, cộng 5 `# type: ignore[valid-type]` **sai mã lỗi** (suppress không đúng thứ đang nổ, lại bị đếm là unused). Sửa đúng ~6 dòng: khai `Callable[..., Identity]` + `_session() -> AsyncIterator[AsyncSession]`, xoá ignore thừa. **Sửa type thật, KHÔNG suppress** — đúng nguyên tắc F2 đặt ra. Kết quả: mypy 12 → **0**.
GATE: .venv/bin/python -m pytest tests/ -q -m 'not live' -x
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (NÂNG từ low theo FLOOR RULE, không phải phán đoán: amendment b2+ kéo api/inbox.py + api/admin.py — cả hai trong RISK_PATHS — vào ALLOWED_FILES, nên floor ép ≥ medium. Spine chặn checkpoint cho tới khi sửa. Yêu cầu của medium đã thoả: ANCHOR confirm = Wyatt duyệt b2+ trước khi tôi sửa api/; reviewer gate = APPROVE 6/6 claim. Nội dung sửa vẫn là annotation thuần, không đổi hành vi runtime.)
REVIEW: PASS ref=docs/reviews/06-F2-auto-verdict.json
BLOCKED_BY: (đã gỡ) F1 ✅ DONE
<!-- /ADP -->

12. `tests/conftest.py` + factory; refactor test hiện có sang fixture chung **chỉ khi không đổi ý nghĩa assert**.
13. Mở rộng mypy ci.yml:70 → `mypy app agent retrieval parsing storage db api auth bridge tools`.
14. Sửa mọi lỗi type lộ ra (KHÔNG `# type: ignore` hàng loạt, KHÔNG hạ `strict`).
15. Chạy GATE_FULL. Đóng ISSUE-014 trong `docs/memory/KNOWN_ISSUES.md`.
16. **STOP+WAIT.**

---

## §8 — DB Changes

**Alembic 0003** (`down_revision = "0002"`) — identity type theo PRE-F01 (**đề xuất TEXT**):

- `conversations`: `id Text PK`, `shop_id Text NOT NULL`, `customer_id Text NOT NULL`, `channel Text NOT NULL` (zalo|messenger…), `external_thread_id Text`, `last_inbound_at TIMESTAMPTZ NULL`, `window_status Text DEFAULT 'active'`, `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`. Index `(shop_id, last_inbound_at DESC)`.
  > `last_inbound_at` + `window_status` land LUÔN ở đây ⇒ **Spec 03 migration 0006 không còn cần ALTER bảng ma** (0006 nên chuyển thành CANCELLED hoặc rút gọn).
- `customers`: `id Text PK`, `shop_id Text NOT NULL`, `external_id Text NOT NULL` (id phía kênh), `display_name Text NULL`, `created_at TIMESTAMPTZ`. Unique `(shop_id, channel, external_id)`. Index `(shop_id, created_at DESC)`.
- `order_drafts`: `id Text PK`, `shop_id Text NOT NULL`, `conversation_id Text NOT NULL FK→conversations.id`, `customer_id Text NOT NULL FK→customers.id`, `items JSONB NOT NULL`, `total_amount NUMERIC NULL`, `status Text NOT NULL DEFAULT 'draft'`, `created_at TIMESTAMPTZ`. Index `(shop_id, status, created_at DESC)`.
  > CHỈ là chỗ chứa đơn AI trích + seller duyệt. **KHÔNG** phải order state machine (đó là GĐ1 Spec 07).
- `pending_reply`: add FK `conversation_id → conversations.id`, `customer_id → customers.id` (theo PRE-F02).

**Sửa kèm Spec 03 §8** (docs-only, KHÔNG code): DDL 0003/0004/0005 đổi `UUID` → `TEXT` cho `shops.id` / `shop_id` / `conversation_id` để khớp on-disk.

- NEVER edit migration đã apply — thêm revision mới.
- Mọi bảng mới đều có `shop_id` + index dẫn đầu `shop_id` (R1.22 analog).
- `downgrade()` phải thật và test được (GATE_FULL F0 chạy upgrade→downgrade→upgrade).

---

## §9 — i18n Keys

Không có UI trong spec này (§3 out-of-scope loại `web/`). **N/A.** Nếu F1 sinh message lỗi user-facing → dùng cơ chế i18n như spec 01 §9, KHÔNG hardcode chuỗi.

---

## §10 — Post-checks

```
.venv/bin/ruff check . && .venv/bin/ruff format --check .
.venv/bin/mypy app agent retrieval parsing storage db api auth bridge tools
.venv/bin/python -m pytest tests/ -q -m 'not live'
.venv/bin/alembic upgrade head && .venv/bin/alembic downgrade -1 && .venv/bin/alembic upgrade head
python .claude/hooks/guardrail.py $(git diff --name-only HEAD | grep '\.py$')

Tenant-isolation adversarial (thủ công, bắt buộc F0):
  Với TỪNG bảng mới: tạo row shop A → repo scope shop B → phải KHÔNG thấy row.
  Expected: 3/3 bảng reject.

Migration parity:
  alembic upgrade head trên DB rỗng → so schema với db/models.py (không lệch cột/index).

Reviewer subagent: S-checklist adapt — S1 shop_id từ JWT không từ body · S10 namespace isolation
  · S-new: mọi query bảng mới có WHERE shop_id SQL-level?
```

---

## §11 — Deliverables

- `db/models.py` +3 model · `db/repos.py` +repo · `db/migrations/versions/0003_foundation_entities.py`
- `channels/{__init__,base}.py` · `channels/zalo/{__init__,adapter}.py` · `api/webhook.py` (generic shape, chưa mount)
- `tests/{test_foundation_models,test_channel_abstraction,conftest}.py`
- `.github/workflows/ci.yml` (mypy mở rộng)
- Spec 03 §8 patched (UUID→TEXT) + Spec 03 phase 0006 note
- `docs/memory/KNOWN_ISSUES.md` — ISSUE-014 CLOSED
- Commit pattern: `adp/06-Foundation phase-F{0,1,2}: <concern>`

---

## §12 — Constraints (STOP conditions + anti-patterns)

- **STOP+WAIT** sau mỗi phase. F0 = per-step confirm (RISK high proposed).
- **ALLOWED_FILES là hard-bound** — không touch file ngoài danh sách dù "tiện tay".
- **TDD bắt buộc:** gate test viết trước, confirm ĐỎ, rồi mới impl. Không tự thuật "passed" — stop-gate chạy thật.
- **KHÔNG migrate `shop_id` Text→UUID** trong spec này (xem PRE-F01).
- **KHÔNG mount `api/webhook.py`** — thiếu concrete `Drafter`, mount = mở đường sống chưa qua policy_gate.
- **KHÔNG đụng** embedder/LLM/Together (chờ ADR PRE-007), `api/inbox.py`, `web/`, `agent/orchestrator.py`, `agent/policy_gate.py`, `_EMBED_DIM`.
- **KHÔNG hạ `mypy strict`** để CI xanh — sửa type thật.
- **Bảng mới thiếu `shop_id` scope SQL-level = BLOCK.** Post-filter không tính (R1.22).
- **Dev fallback phải gate `OHANA_ENV == "dev"` + fail-loud ngoài dev** — docstring "not production-safe" KHÔNG làm nó an toàn (đã dính 2 lần ở spec 04).
- **Brief cho executor phải TRÍCH spec, không paraphrase** — paraphrase là chỗ scope trôi (ISSUE-012).
- **Không self-certify DONE** — chỉ qua `adp-checkpoint.sh`.
- **Không tự hạ RISK tier** — Wyatt ký; floor rule enforce.
- Một patch = một concern. Bug phụ phát hiện → ghi KNOWN UNCOVERED, không fix kèm.

---

## §13 — Post-check gate table

| Check | Command | Phase |
|---|---|---|
| pytest (không live) | `.venv/bin/python -m pytest tests/ -q -m 'not live'` | All |
| ruff | `.venv/bin/ruff check . && .venv/bin/ruff format --check .` | All |
| mypy (mở rộng) | `.venv/bin/mypy app agent retrieval parsing storage db api auth bridge tools` | F2+ |
| migration round-trip | `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` | F0 |
| cross-shop reject | `pytest tests/test_foundation_models.py tests/test_tenant_isolation.py -x -q` | F0 |
| channel contract | `pytest tests/test_channel_abstraction.py -x -q` | F1 |
| guardrail headless | `python .claude/hooks/guardrail.py <changed .py>` | All |

---

## §14 — Tracking

| Phase | Concern | RISK (proposed) | STATUS | BLOCKED_BY | EVIDENCE |
|---|---|---|---|---|---|
| PRE | F01 identity type · F02 pending_reply empty · F03 alembic head · F04 no-provider-touch | — | TODO | Wyatt (F01) | — |
| F0 | Core data model + Alembic 0003 + FK | **high** | TODO | PRE-F01, PRE-F02 | — |
| F1 | Channel abstraction (Zalo → Protocol) | **medium** | TODO | F0 | — |
| F2 | conftest + mypy mở rộng | **low** | TODO | F1 | — |

**Wyatt ĐÃ KÝ 2026-07-18:**
- [x] **PRE-F01 identity type: `TEXT`** ✅ — KHÔNG migrate sang UUID. Hệ quả bắt buộc: sửa Spec 03 §8 DDL (0003/0004/0005) từ `UUID` → `TEXT` cho `shops.id` / `shop_id` / `conversation_id`.
- [x] **RISK tier final = giữ nguyên đề xuất** ✅ — **F0 `high`** (per-step confirm + Wyatt sync diff review) · **F1 `medium`** (1 confirm tại ANCHOR + reviewer gate) · **F2 `low`** (auto-flow, reviewer light).
- [x] **FK lên `pending_reply`: CÓ** ✅ — `conversation_id → conversations.id`, `customer_id → customers.id`. Cách thi hành vẫn theo PRE-F02: rỗng ⇒ FK thẳng; có data ⇒ backfill Conversation/Customer từ giá trị đang có TRƯỚC khi add constraint.

> RISK tier = **proposed**, Wyatt finalize (DEC-019 floor rule). EVIDENCE do `adp-checkpoint.sh` ghi, KHÔNG phải spec author. REVIEW do `adp-review.sh stamp`; RISK:high cần human review artifact bound cùng diff.
