# 10-Task-OhanaAISeller-ConversationHistory

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-20 "tạo spec GD0-HISTORY") -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng safety→trust→stability→growth. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Conversation history — ghi + đọc `Message`, load last-N vào draft |
| Parent | `GD0-HISTORY` (L1 `docs/ROADMAP.md` §4.1, thêm ở commit `4169567`) |
| Depends-on | Spec 06 (Foundation, DONE) · Spec 09 (conversation race, DONE — lấy `0005`) |
| Unblocks | Mount `api/webhook.py`; và là tiền đề của persona (`GD0-SHOPS`) |
| Owner | R: Claude · A: Wyatt |
| Branch | `main` (commit thẳng — khớp spec 06/07/08/09) |
| Spec type | Feature · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

**Bảng `messages` tồn tại nhưng không dùng được, vì hai lý do độc lập.**

**(1) Không liên kết được với conversation.** `db/models.py:51-70` — `Message` chỉ có `id · shop_id · role · content · created_at`, index duy nhất `idx_msg_shop_created (shop_id, created_at)`. **Không có `conversation_id`, không có `customer_id`, không có FK nào.**

Đây là entity DUY NHẤT trong repo không có FK. `Conversation`, `OrderDraft`, `PendingReply` đều đã nhận composite FK `(shop_id, X) → parent(shop_id, id)` ở spec 06 F0 — `Message` bị bỏ sót. Hệ quả trực tiếp: câu *"load last N message của conversation này"* **không viết được**, vì bảng không biết message thuộc conversation nào. Cùng lắm chỉ lọc được theo `shop_id` — tức trộn chung mọi khách của một shop.

**(2) Chưa từng được ghi.** `grep "Message("` toàn repo ngoài định nghĩa model = **0 hit**. `agent/orchestrator.py:57-103` không ghi ở cả hai nhánh (`auto_send` và `park`). `api/webhook.py` đã resolve `(customer_id, conversation_id)` rồi vứt đi sau khi gọi orchestrator.

Cùng họ **ISSUE-020** (`last_inbound_at`/`window_status` luồng qua schema, không luồng qua code) — nhưng nặng hơn: ISSUE-020 làm một scheduler trả rỗng, cái này làm AI **không trả lời được câu thứ hai**.

**Vì sao là chặn, không phải nice-to-have.** Khách Zalo nhắn *"cái áo đó còn size M không"*. Không có history thì "cái áo đó" vô nghĩa — AI không có gì để phân giải đại từ. Đây không phải vấn đề "nhân cách nhất quán đa lượt" (đó là persona, `GD0-SHOPS`); đây là **không hoạt động được từ lượt thứ 2**.

**Chưa chảy máu hôm nay:** `api/webhook.py` chưa mount trong `app/main.py` + có guard `enabled=False` (503) ⇒ đường seller **zero traffic**. Lỗi tiềm ẩn có ngày hết hạn rõ ràng: ngày mount webhook.

### Audit on-disk 2026-07-20 — HEAD `4169567`, đo bằng lệnh thật

1. ✅ `Message` thiếu `conversation_id`/`customer_id`/FK — `db/models.py:51-70`.
2. ✅ `grep "Message("` ngoài model = 0 hit. Bảng chưa từng được ghi.
3. ✅ `db/repos.py` có `ConversationRepo` + `PendingReplyRepo` (đều `__init__(session, *, shop_scope)`). **Không có `MessageRepo`.**
4. ✅ `agent/orchestrator.py:78` gọi `drafter.draft(shop_id=, customer_id=, message=)` — **không truyền history**. `Drafter` Protocol tại `:46`.
5. ✅ `api/webhook.py:88-95` đã có `(customer_id, conversation_id)` từ `resolve_conversation()` trước khi gọi `receive_and_draft`.
6. ✅ Migration mới nhất trên đĩa: `0005_conversation_unique.py` ⇒ spec này lấy **`0006`**. Spec 03 (BLOCKED) giữ chỗ `0006/0007/0008` — **va chạm, xem PRE-1001**.
7. ⚠️ **`api/inbox.py` approve KHÔNG gửi gì cả** — docstring `:11-13` ghi rõ: *"approve just flips the status. A separate worker (Phase 3+) drains `approved` rows and calls the sender."* Worker đó **chưa tồn tại**. ⇒ nhánh `park` **không có hook nào** để ghi message-đã-gửi. Xem §14 Q2.
8. ⚠️ `approve` endpoint **không nhận body** ⇒ seller hiện **không sửa được** draft trước khi duyệt. Ảnh hưởng câu hỏi `role='seller'` vs `'assistant'`. Xem §14 Q3.

---

## §2 — Goal

**VI:** Mỗi tin nhắn vào/ra được ghi vào `messages` gắn đúng `conversation_id` với composite FK chặn cross-tenant ở tầng Postgres; `Drafter` nhận last-N message của **đúng** conversation đó, có cap. Chứng minh bằng test lượt-2 dùng đại từ, không phải bằng lý luận.

**EN:** Every inbound and outbound message is persisted against its `conversation_id` with a composite FK that Postgres enforces across tenants; the `Drafter` receives the last N messages of *that* conversation, capped. Proven by a second-turn pronoun test, not by argument.

---

## §3 — Scope

- `db/models.py` — `Message` += `conversation_id`, `customer_id` (Text NOT NULL) + 2 composite FK + index `(shop_id, conversation_id, created_at)`.
- `db/migrations/versions/0006_message_conversation_fk.py` — thêm cột + FK + index.
- `db/repos.py` — `MessageRepo(session, *, shop_scope)` với `append(...)` + `last_n(conversation_id, *, limit)`.
- `api/webhook.py` — ghi inbound message (role=`user`) sau `resolve_conversation()`, TRƯỚC `receive_and_draft`.
- `agent/orchestrator.py` — nhận + truyền history vào `Drafter`; ghi outbound message ở nhánh `auto_send`.
- `tests/test_message_history.py` (mới).

### Out of scope (cố ý)

- ❌ **Mount `api/webhook.py`** — cần PRE-004 (Zalo creds + signature). Spec này chỉ gỡ *một* điều kiện tiên quyết.
- ❌ **Sender worker drain `approved` rows** — chưa tồn tại (audit #7). Nhánh `park` do đó chưa ghi được message-đã-gửi; xem §14 Q2.
- ❌ **Persona / `shop_profile`** — `GD0-SHOPS`, spec riêng.
- ❌ **Sửa draft khi approve** — cần đổi API `inbox.approve`; xem §14 Q3.
- ❌ **Tóm tắt history khi vượt cap** — chỉ cắt cứng ở spec này. Tóm tắt là bài toán chất lượng, cần eval (`GD0-EVAL`).

---

## §4 — Safety Gate Check (trục Ohana)

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Composite FK `(shop_id, conversation_id)` → `conversations(shop_id, id)` khiến Postgres TỪ CHỐI message trỏ conversation của shop khác. FK đơn KHÔNG chặn được — nó chỉ đòi id tồn tại, không đòi cùng shop. Đọc qua `MessageRepo(shop_scope=)` ⇒ scope ở tầng SQL, không post-filter. | PASS |
| **User trust** | History đúng ⇒ AI phân giải được đại từ, không hỏi lại thứ khách vừa nói. Đây là điều kiện để sản phẩm dùng được, không phải cải thiện. | PASS |
| **Stability** | Bảng rỗng (PRE-1002 ✅ đo thật 2026-07-20 = 0 row) ⇒ thêm NOT NULL không cần backfill. Migration reversible thật (drop cột), khác `0004`. | PASS |
| **Growth** | Gỡ 1 trong 2 điều kiện tiên quyết của mount webhook (còn lại: PRE-004). | PASS |

**RED FLAG scan:**

- [x] **FK phải composite, không phải đơn.** Đây chính là lỗi spec 06 F0 đã vá cho 3 bảng khác. Test phải chứng minh cross-shop bị TỪ CHỐI, không chỉ chứng minh FK tồn tại.
- [x] **`last_n` phải scope shop_id ở SQL.** Truy vấn chỉ lọc `conversation_id` là lỗ R1.22 — `conversation_id` là Text tự sinh, không chứng minh được quyền sở hữu.
- [x] **Ghi message KHÔNG được nằm ngoài `policy_gate`.** Ghi `messages` là lưu trữ, không phải gửi. Nhưng nếu ai đó sau này drain `messages` để gửi thì bypass gate — docstring `MessageRepo` phải nói rõ nó là **append-only log**, không phải hàng đợi gửi.
- [x] **NOT NULL trên bảng đã có dữ liệu sẽ FAIL.** ✅ Đã đo thật (0 row) — KHÔNG suy từ "grep 0 hit", vì code-không-ghi không chứng minh bảng rỗng.
- [ ] ⚠️ **Cap N chưa đo** — cùng họ ISSUE-022. Đặt số tạm để có ràng buộc cứng, không phải vì tin nó đúng.

---

## §5 — Source files

Đọc TRƯỚC khi sửa: `db/models.py` (§Message + §PendingReply cho pattern composite FK) · `db/repos.py` (pattern `shop_scope`) · `db/migrations/versions/0005_conversation_unique.py` (style migration + docstring) · `agent/orchestrator.py` · `api/webhook.py` · `api/inbox.py` (hiểu vì sao park không có hook gửi) · `channels/identity.py`.

---

## §6 — PRE checks

```
PRE-1001: Số migration `0006` đã bị ai lấy chưa — kiểm CẢ đĩa LẪN docs/tasks/.
  Trạng thái: ⚠️ VA CHẠM (lần thứ BA của cùng một loại — xem memory
              "số migration cấp theo thứ tự LAND").
              Trên đĩa: mới nhất `0005`. Trong docs: spec 03 (BLOCKED) giữ chỗ
              `0006/0007/0008` sau khi spec 09 đẩy nó một nhịp.
  Xử lý:      spec 10 land TRƯỚC (spec 03 chờ Tân) ⇒ spec 10 lấy `0006`,
              spec 03 dịch sang `0007/0008/0009`. Sửa spec 03 TRONG phase H0.
  Verify:     ls db/migrations/versions/ && grep -n "000[6-9]" docs/tasks/03-*.md

PRE-1002: `messages` có bao nhiêu row THẬT (NOT NULL có backfill được không)?
  Trạng thái: ✅ ĐO 2026-07-20 trên Postgres THẬT — **count(*) = 0**.
              DB `ohana` @ 127.0.0.1:5432 · PG **16.14** · alembic head **0005**.
              Cùng lần chạy xác nhận `messages` đúng 5 cột (id, shop_id, role,
              content, created_at) — không có conversation_id/customer_id, khớp
              audit đọc từ `db/models.py`. Và `0006` còn trống trên DB thật.
  Verify:     .venv/bin/python -c "import psycopg;c=psycopg.connect('postgresql://ohana:ohana@127.0.0.1:5432/ohana');\
              print(c.execute('select count(*) from messages').fetchone())"
              (⚠️ `psql` KHÔNG có trên máy Wyatt — dùng psycopg trong venv.
               Và URL trong DATABASE_URL là dạng SQLAlchemy `postgresql+psycopg://`,
               psycopg cần bỏ hậu tố `+psycopg`.)
  Kết luận:   ADD COLUMN NOT NULL chạy được, KHÔNG cần tách migration,
              KHÔNG cần backfill. H0 giữ RISK: medium — điều kiện nâng high
              (>0 row) không kích hoạt.

PRE-1003: Cap N message + cap ký tự — Wyatt chốt.
  Trạng thái: ✅ WYATT KÝ 2026-07-20 — 20 message HOẶC 4000 ký tự, cái nào chạm trước.
              Số ĐẶT TẠM, chưa đo tokenizer (§14 Q1) — không trích như đã đo.

PRE-1004: Nhánh `park` ghi message-đã-gửi ở đâu — Wyatt chốt.
  Trạng thái: ✅ WYATT KÝ 2026-07-20 — **CHƯA GHI** ở spec này. Khi worker gửi
              land, nó ghi ngay SAU `send()` thành công, đối xứng `auto_send`.
              Hệ quả đã chấp nhận tường minh: xem §14 Q2.

PRE-1005: `role` khi seller sửa draft rồi gửi — Wyatt chốt.
  Trạng thái: ⏳ ĐỀ XUẤT, chờ ký. Xem §14 Q3.
```

---

## §7 — Execute Steps

### Phase H0 — Schema: `Message` gắn conversation + composite FK

<!-- ADP:PHASE H0 -->
STATUS: DONE
EVIDENCE: commit=e4971e0, gate_exit=0, duration=17s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=31d5d34fc39c,tier=medium), smoke=PASS(bound=31d5d34fc39c), ran=2026-07-20T13:23
ROADMAP: GD0-HISTORY
GOAL: `messages` có `conversation_id`/`customer_id` NOT NULL + 2 composite FK; Postgres TỪ CHỐI message trỏ conversation của shop khác (test chứng minh bằng `IntegrityError`, không bằng đọc code); index `(shop_id, conversation_id, created_at)` tồn tại; migration up→down→up sạch.
APPROACH: Đúng shape composite FK mà spec 06 F0 đã áp cho `Conversation`/`OrderDraft`/`PendingReply` — `ForeignKeyConstraint(["shop_id","conversation_id"], ["conversations.shop_id","conversations.id"])`. Lý do phải composite chứ không FK đơn đã viết sẵn trong docstring `PendingReply`: FK đơn chỉ đòi id TỒN TẠI, không đòi cùng shop, nên nó cho phép message của shop A trỏ conversation shop B và Postgres im lặng chấp nhận. Thêm `customer_id` luôn (cùng migration) để đối xứng với `PendingReply` và để truy vấn "mọi message của khách này xuyên conversation" không phải join. Index mới đặt cạnh `idx_msg_shop_created` chứ không thay nó — cái cũ phục vụ truy vấn theo shop, cái mới phục vụ đọc history.
ALLOWED_FILES: db/models.py, db/migrations/versions/, tests/test_message_history.py, tests/test_tenant_isolation.py, docs/smokes/, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md, docs/tasks/10-Task-OhanaAISeller-ConversationHistory.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_message_history.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (KÝ: Wyatt 2026-07-20. Floor rule: ALLOWED_FILES giao RISK_PATHS ở `db/migrations`. KHÔNG đề xuất high: thêm cột + FK, không đổi hành vi tiền/gửi; reversible thật; bảng rỗng theo PRE-1002. Nếu PRE-1002 trả > 0 row ⇒ nâng lên high, vì lúc đó có backfill trên dữ liệu thật.)
BLOCKED_BY: PRE-1001 ✅ (dịch spec 03 → 0007/0008/0009), PRE-1002 ✅ (đo 2026-07-20 = 0 row)
SMOKE: PASS ref=docs/smokes/10-H0.md
REVIEW: PASS ref=docs/reviews/10-H0-auto-verdict.json
<!-- /ADP -->

1. `tests/test_message_history.py` (**RED trước**): (a) 2 cột tồn tại + NOT NULL, đọc từ `information_schema`; (b) 2 composite FK tồn tại, đọc từ `pg_constraint`; (c) **cross-tenant bị TỪ CHỐI** — insert message `shop_id='A'` trỏ conversation của shop `B` ⇒ `IntegrityError`; (d) index tồn tại; (e) migration up→down→up sạch.
2. Chạy PRE-1002 trên Postgres thật. **> 0 row ⇒ STOP**, tách migration.
3. `db/models.py`: thêm 2 cột + `ForeignKeyConstraint` ×2 + `Index`.
4. Viết `0006_message_conversation_fk.py` (docstring theo style `0005`: nói rõ destructive hay không, và `downgrade` mất gì).
5. Sửa spec 03: dịch `0006/0007/0008` → `0007/0008/0009` (PRE-1001).
6. **STOP+WAIT** (ANCHOR).

---

### Phase H1 — Write path: ghi inbound + outbound

<!-- ADP:PHASE H1 -->
STATUS: DONE
EVIDENCE: commit=e6d7ef8, gate_exit=0, duration=11s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=4fba514be60e,tier=medium), smoke=PASS(bound=4fba514be60e), ran=2026-07-20T13:44
ROADMAP: GD0-HISTORY
GOAL: Một tin nhắn khách đi qua webhook để lại ĐÚNG 1 row `role='user'` gắn đúng `conversation_id`; nhánh `auto_send` để lại thêm ĐÚNG 1 row `role='assistant'`; nhánh `park` KHÔNG để lại row assistant; `MessageRepo` từ chối ghi/đọc ngoài `shop_scope`.
GOAL-AMEND (Wyatt ký 2026-07-20, trước khi H1 bắt đầu): vế "ghi 2 lần cùng payload không nhân đôi row (idempotency theo quyết định PRE-1004)" **ĐÃ GỠ**. Ba lý do: (1) trích dẫn sai — PRE-1004 nói về nhánh `park`, không nói gì về idempotency; (2) sau H0 `messages` KHÔNG có khoá dedup nào (`external_message_id`/unique), nên không có gì để nhận ra payload trùng; (3) cơ chế dedup là `webhook_event_log` (`event_id` PRIMARY KEY) thuộc **spec 03 Phase 2**, class `external`, BLOCKED chờ Tân (PRE-004).
  ⚠️ Hệ quả CHẤP NHẬN tường minh: Zalo retry webhook sẽ nhân đôi tin khách trong `messages`. Chưa chảy máu vì `api/webhook.py` chưa mount + `enabled=False`; ngày hết hạn = ngày mount.
  🚫 KHÔNG vá bằng select-then-insert ở tầng code: đó đúng là ISSUE-017 mà spec 09 vừa đóng — hai webhook đồng thời vẫn lọt cả hai, test đơn luồng vẫn xanh, và nó chỉ TRÔNG như đã vá. Dedup phải ở tầng DB hoặc không làm.
APPROACH: `MessageRepo(session, *, shop_scope)` đối xứng với `PendingReplyRepo` — `shop_id` BAKED từ scope repo, không nhận từ tham số, nên caller sai cũng không ghi lệch shop được. Ghi inbound ở `api/webhook.py` NGAY SAU `resolve_conversation()` và TRƯỚC `receive_and_draft`: nếu drafter/LLM nổ thì tin khách vẫn nằm trong log — mất tin khách là loại mất mát không phục hồi được, mất draft thì retry được. Ghi outbound chỉ ở nhánh `auto_send`, ngay SAU `sender.send()` thành công — ghi trước khi gửi sẽ tạo lịch sử khai điều chưa xảy ra. Nhánh `park` CỐ Ý chưa ghi: `PendingReply` đã là bản ghi của nó, và chưa có worker nào thực sự gửi (audit #7) — ghi lúc approve sẽ khai "đã gửi" trong khi không ai gửi. Docstring `MessageRepo` phải nói rõ: **append-only log, KHÔNG phải hàng đợi gửi** — để lần sau không ai drain nó mà bypass `policy_gate`.
ALLOWED_FILES: db/repos.py, api/webhook.py, agent/orchestrator.py, tests/test_message_history.py, tests/test_orchestrator.py, docs/tasks/10-Task-OhanaAISeller-ConversationHistory.md, docs/reviews/, docs/smokes/
ALLOWED_FILES-AMEND: `tests/test_orchestrator.py` thêm giữa phase. Lý do: `test_safe_high_confidence_auto_enabled_sends` dùng id giả `conv1`/`cust1` không có parent — trước H1 nhánh auto_send không ghi gì nên không đụng FK; H1 làm nó ghi `messages` ⇒ composite FK của H0 từ chối. Sửa = thêm 1 lời gọi `_seed_parents` đã có sẵn trong file. KHÔNG nới lỏng assertion nào.
GATE: .venv/bin/python -m pytest tests/test_message_history.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (KÝ: Wyatt 2026-07-20 — giữ medium, KHÔNG nâng high. Floor rule: giao RISK_PATHS ở `agent/orchestrator.py` + `api/webhook.py`. Đây là phase đáng cân nhắc nhất trong spec: nó đổi hành vi của orchestrator — luồng duy nhất đứng giữa AI và khách hàng. Không đổi tiền, nhưng đổi cái quyết định gửi gì cho ai.)
BLOCKED_BY: H0 DONE (PRE-1004 ✅ đã ký)
SMOKE: PASS ref=docs/smokes/10-H1.md
REVIEW: PASS ref=docs/reviews/10-H1-auto-verdict.json
<!-- /ADP -->

1. Test (**RED trước**): (a) inbound → 1 row `user` đúng conversation; (b) `auto_send` → thêm 1 row `assistant`; (c) `park` → KHÔNG có row assistant (khẳng định quyết định, để lần sau đổi ý thì test đỏ chứ không trôi âm thầm); (d) `MessageRepo(shop_scope='A').last_n(conv_của_B)` trả **rỗng**, không raise — không leak sự tồn tại; (e) `sender.send` raise ⇒ KHÔNG có row assistant.
2. `MessageRepo` trong `db/repos.py`.
3. `api/webhook.py`: ghi inbound.
4. `agent/orchestrator.py`: ghi outbound nhánh `auto_send`.
5. **STOP+WAIT**.

---

### Phase H2 — Read path: last-N vào `Drafter` + cap

<!-- ADP:PHASE H2 -->
STATUS: DONE
EVIDENCE: commit=84aac7f, gate_exit=0, duration=13s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=5ea5bc2f8ba9,tier=medium), smoke=PASS(bound=5ea5bc2f8ba9), ran=2026-07-20T20:25
ROADMAP: GD0-HISTORY
GOAL: `Drafter.draft()` nhận `history: list[Message]` của ĐÚNG conversation đó, thứ tự cũ→mới, cắt theo cap PRE-1003; test lượt-2 dùng đại từ chứng minh history tới được drafter; vượt cap thì cắt TỪ ĐẦU (giữ tin mới nhất) và số lượng cắt đo được.
APPROACH: Mở rộng Protocol `Drafter` thêm tham số `history` — đây là breaking change của Protocol, nhưng hiện **zero implementation** (audit #4) nên chi phí bằng 0; làm bây giờ rẻ hơn làm sau khi có impl thật. Cắt từ ĐẦU chứ không từ cuối: tin mới nhất là tin đang cần trả lời, tin cũ nhất mới là thứ bỏ được. Cap kép (số lượng + ký tự) vì một mình số lượng không chặn được 20 tin mỗi tin 3000 ký tự. Test lượt-2 assert **history tới được drafter với nội dung đúng** qua fake drafter — KHÔNG assert LLM trả lời đúng: cái đó cần `-m live` + eval, và một test phụ thuộc chất lượng LLM là test sẽ đỏ ngẫu nhiên.
ALLOWED_FILES: agent/orchestrator.py, db/repos.py, tests/test_message_history.py, tests/test_orchestrator.py, tests/test_channel_abstraction.py, docs/tasks/10-Task-OhanaAISeller-ConversationHistory.md, docs/memory/KNOWN_ISSUES.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_message_history.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (KÝ: Wyatt 2026-07-20. Floor rule: giao RISK_PATHS ở `agent/orchestrator.py`. Đổi signature Protocol, không đổi hành vi gửi.)
BLOCKED_BY: H1 DONE (PRE-1003 ✅ đã ký)
SMOKE: PASS ref=docs/smokes/10-H2.md
REVIEW: PASS ref=docs/reviews/10-H2-auto-verdict.json
<!-- /ADP -->

1. Test (**RED trước**): (a) lượt 2 — fake drafter nhận đúng history của lượt 1, thứ tự cũ→mới; (b) history của conversation KHÁC không lẫn vào; (c) vượt cap số lượng ⇒ giữ N mới nhất; (d) vượt cap ký tự ⇒ cắt thêm, tin mới nhất luôn còn; (e) conversation mới ⇒ history rỗng, không nổ.
2. `MessageRepo.last_n(conversation_id, *, limit)` — `ORDER BY created_at DESC LIMIT N` rồi đảo, scope `shop_id` ở SQL.
3. `Drafter` Protocol += `history`; `receive_and_draft` load + truyền.
4. Ghi ISSUE mới cho cap chưa đo (trỏ ISSUE-022 cùng họ).
5. **STOP+WAIT**.

---

## §8 — DB Changes

**Migration `0006_message_conversation_fk.py` — KHÔNG destructive** (với điều kiện PRE-1002 = 0 row).

```sql
ALTER TABLE messages ADD COLUMN conversation_id TEXT NOT NULL;
ALTER TABLE messages ADD COLUMN customer_id     TEXT NOT NULL;

ALTER TABLE messages ADD CONSTRAINT fk_messages_conversation_same_shop
  FOREIGN KEY (shop_id, conversation_id) REFERENCES conversations (shop_id, id);
ALTER TABLE messages ADD CONSTRAINT fk_messages_customer_same_shop
  FOREIGN KEY (shop_id, customer_id)     REFERENCES customers (shop_id, id);

CREATE INDEX idx_msg_shop_conv_created ON messages (shop_id, conversation_id, created_at);
```

`downgrade` = drop index + 2 FK + 2 cột. **Reversible về schema; KHÔNG reversible về dữ liệu** — drop cột là mất liên kết conversation của mọi message đã ghi. Ghi rõ trong docstring: đây là cùng loại cảnh báo với `0004`, dù nhẹ hơn.

⚠️ `ADD COLUMN ... NOT NULL` không default sẽ **FAIL** nếu bảng có row. Đó là hành vi đúng — bắt người vận hành nhìn dữ liệu trước khi quyết backfill. PRE-1002 tồn tại để biết trước, không phải để phát hiện lúc chạy.

---

## §10 — Post-checks

```bash
.venv/bin/python -m pytest tests/ -q -m 'not live'
.venv/bin/mypy app agent retrieval parsing storage db bridge tools
.venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
alembic upgrade head && alembic downgrade -1 && alembic upgrade head
grep -rn "Message(" --include="*.py" agent api db channels   # phải có hit — trước spec này = 0
```

**SMOKE** (§ADP — test đo môi trường TEST, smoke đo môi trường THẬT): chạy app thật, POST webhook giả 2 lượt cùng khách, đọc DB xác nhận 2 row `user` cùng `conversation_id`, và lượt 2 drafter nhận history. Điền OBSERVED bằng output THẬT vào `docs/smokes/10-H{0,1,2}.md`. **Ghi dòng SMOKE TRƯỚC khi stamp** — stamp trước rồi ghi sau ⇒ hash lệch ⇒ REFUSE.

---

## §11 — Deliverables

| File | Hành động |
|---|---|
| `db/models.py` | sửa — `Message` += 2 cột, 2 FK, 1 index |
| `db/migrations/versions/0006_message_conversation_fk.py` | mới |
| `db/repos.py` | sửa — `MessageRepo` |
| `api/webhook.py` | sửa — ghi inbound |
| `agent/orchestrator.py` | sửa — ghi outbound + truyền history |
| `tests/test_message_history.py` | mới |
| `docs/tasks/03-*.md` | sửa — dịch số migration (PRE-1001) |

Commit: `adp/10-Task-OhanaAISeller-ConversationHistory phase-H{0,1,2}: <concern>` — một concern một commit.

---

## §12 — Constraints

**STOP nếu:** PRE-1003/1004/1005 chưa có chữ ký Wyatt khi tới phase cần nó · RETRY chạm 3/3.

**Anti-pattern — KHÔNG làm:**

- 🚫 FK đơn thay composite — không chặn được cross-tenant, và đó là toàn bộ lý do phase H0 tồn tại.
- 🚫 `last_n` chỉ lọc `conversation_id` mà không có `shop_id` ở SQL (R1.22).
- 🚫 Ghi outbound TRƯỚC khi `sender.send()` thành công.
- 🚫 Ghi message ở nhánh `park` khi chưa có ai gửi — lịch sử khai điều chưa xảy ra.
- 🚫 Drain `messages` để gửi — bypass `policy_gate`.
- 🚫 Tự chọn số cap rồi ghi vào spec như quyết định đã ký (PRE-1003 chờ Wyatt).
- 🚫 Self-certify DONE ngoài `adp-checkpoint.sh`.
- 🚫 Mount `api/webhook.py` trong spec này.

---

## §13 — Tracking

| Phase | Concern | STATUS | RISK (đã ký) | Blocked by |
|---|---|---|---|---|
| H0 | Schema + composite FK + migration `0006` | TODO | **medium** (ký) | PRE-1001 |
| H1 | Write path (inbound + auto_send) | TODO | **medium** (ký) | H0 |
| H2 | Read path last-N + cap | TODO | **medium** (ký) | H1 |

---

## §14 — Open questions (Wyatt quyết — spec KHÔNG tự chốt)

**Q1 · Cap N message + cap ký tự (PRE-1003).** ✅ **WYATT KÝ 2026-07-20.**
Chốt: **20 message HOẶC 4000 ký tự, cái nào chạm trước**. Cơ sở: cap persona 2000 ký tự (`GD0-SHOPS`) + 4000 history ≈ 1800 token, còn chỗ cho system prompt + tool schema trong ngân sách một lượt. **Con số này chưa đo** — cùng họ ISSUE-022, suy từ ước lượng ký tự→token tiếng Việt ≈ 3.3, chưa chạy tokenizer Llama-3.3 thật. Đặt số để có ràng buộc cứng từ đầu; đo lại khi có hội thoại thật.

**Q2 · Nhánh `park` ghi message-đã-gửi ở đâu (PRE-1004).** ✅ **WYATT KÝ 2026-07-20 — CHƯA GHI.**
Chốt: **chưa ghi ở spec này**. Lý do: `api/inbox.py` approve chỉ flip status, worker gửi chưa tồn tại (audit #7). Ghi lúc approve = lịch sử khai "đã gửi" trong khi không ai gửi — đúng loại sai lệch âm thầm mà repo này đã dính 3 lần. Khi worker land, nó ghi ngay sau `send()` thành công, đối xứng với `auto_send`.
⚠️ Hệ quả đã chấp nhận (Wyatt ký, không phải bỏ sót): reply do seller duyệt **không vào history** cho tới khi worker có. Tức lượt sau AI không thấy điều chính nó đã nói. Đây là lỗ thật, không phải chi tiết — nhưng vá nó bằng cách ghi-khi-approve là đổi một lỗ lấy một lỗ tệ hơn.

**Q3 · `role='seller'` hay `'assistant'` khi seller sửa draft rồi gửi (PRE-1005).**
Đề xuất: `assistant` khi text đi nguyên văn từ AI, `seller` khi người viết/sửa. **Nhưng hôm nay không phân biệt được**: `approve` không nhận body (audit #8) nên seller chưa sửa được gì. ⇒ Câu hỏi này thực chất bị chặn sau Q2 và sau việc `inbox.approve` có nhận text sửa hay không. Đề nghị **để OPEN**, quyết cùng lúc với worker gửi.

**Q4 · `messages` có cần `pending_reply_id` để truy vết draft → message đã gửi không?**
Chưa ai hỏi, nhưng nó quyết định được ở H0 (thêm cột lúc này rẻ) hay phải thêm migration nữa sau. Đề xuất: **chưa thêm** — YAGNI, và `conversation_id` + `created_at` đã đủ để nối thủ công khi debug. Ghi lại ở đây để lần sau không tưởng là bỏ sót.
