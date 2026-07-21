# 14-Task-OhanaAISeller-DraftSchema-Idempotency

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-21 "viết spec ADP" sau DEC-OHANA-05) -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng trục safety→trust→stability→growth, -->
<!-- KHÔNG dùng Survival Framework LR/WP/TV/UR — Ohana không có cột tài chính. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Schema-shaping: draft TTL/snapshot/label + webhook idempotency table |
| Parent | `GD0-DRAFTSCHEMA` + `GD0-INGEST` (L1 `docs/ROADMAP.md` §4.1, thêm v6) |
| Structural source | [`docs/backend-workflow.md`](../backend-workflow.md) §2.1, §2.3, §2.5, §7 (DEC-OHANA-05) |
| Depends-on | Spec 06 (Foundation, DONE) · Spec 09 (Conversation unique, DONE) · Spec 11 (Shops, DONE) |
| **Supersedes** | **`docs/tasks/03-Task-GD0-AcceptanceBackfill.md` Phase 2** (idempotency table) — CHỜ Wyatt ký, §6 PRE-1403 |
| Unblocks | `GD0-INGEST` runtime (ACK+queue+worker) · auto-send evolution GĐ1 (label là training data) |
| Owner | R: Claude · A: Wyatt |
| Branch | `main` (commit thẳng — khớp spec 06–11) |
| Spec type | Schema · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

### 1.1 Workflow §7 bước 3: "sai schema từ đầu là refactor lớn"

`backend-workflow.md` §7 xếp thứ tự cứng: **(1) webhook + idempotency → (2) rules layer → (3) draft schema TTL+snapshot+label**. Lý do §7 nêu thẳng: *"Sai schema từ đầu là refactor lớn. Có `label` field từ ngày một để nuôi §8."* Ba cột này rẻ khi bảng gần rỗng và đắt sau khi có traffic thật — vì lúc đó thêm cột kèm backfill trên dữ liệu shop đang chạy.

Đo trên đĩa 2026-07-21 (HEAD `52f943f`):

1. ✅ `db/models.py::PendingReply` có 11 cột: `reply_id, shop_id, conversation_id, customer_id, draft_text, intent, confidence, status, created_at, decided_by, decided_at`. **KHÔNG có `snapshot`, `expires_at`, `label`.**
2. ✅ `webhook_event_log` KHÔNG tồn tại — chỉ xuất hiện trong comment `db/repos.py:165` + `api/webhook.py:113` ("dedup là `webhook_event_log`, spec 03 Phase 2, BLOCKED").
3. ✅ `messages` KHÔNG idempotent (CLAUDE.md §3): Zalo retry cùng payload ⇒ 2 row, không khoá dedup nào. Cơ chế chống trùng theo thiết kế = `webhook_event_log`, chưa land.
4. ✅ `PendingReplyRepo.mark_decided(reply_id, new_status, decided_by)` — chỗ tự nhiên để set `label`.

### 1.2 Hệ quả nếu để nguyên

- **Không snapshot:** draft chờ duyệt (workflow §2.3 nêu ~30 phút); tồn kho/giá đổi giữa lúc soạn (T0) và lúc seller bấm gửi (T1). Không có snapshot T0 thì §2.5 không phát hiện được drift ⇒ seller duyệt trên số cũ ⇒ oversell/hứa sai. Rủi ro thuộc trục **user trust**.
- **Không label:** workflow §8.1 — auto-send GĐ1 train classifier trên `(tin khách, ý định, label)` từ inbox log. Không ghi từ ngày một ⇒ khi tới GĐ1 phải tích data lại từ đầu (vài shop × 4–8 tuần). Chi phí ghi bây giờ ~0.
- **Không idempotency table:** workflow §2.1 ràng buộc cứng #2 "Idempotent tại DB. Unique constraint trên `(channel, platform_msg_id)`. Không dựa vào cache." Đây là keystone #1. **Bảng + constraint là phần INTERNAL — không cần Zalo creds** (creds chỉ cần cho signature-verify = `GD0-ZALO` external). Tách ra làm được ngay.

### 1.3 ⚠️ Ranh giới: spec này chỉ dựng SCHEMA, KHÔNG dựng runtime

Cả `GD0-DRAFTSCHEMA` lẫn `GD0-INGEST` có phần runtime lớn (ACK-then-process, queue, worker drain, snapshot capture lúc draft, TTL cron expiry, edit endpoint). **Spec này CỐ Ý chỉ bao phần schema + repo surface** — cột/bảng + accessor — để phần runtime sau này land mà không phải migrate dữ liệu. Cùng triết lý spec 11 (dựng `shops` schema, KHÔNG dựng `Drafter`).

Không làm điều đó thì phạm vi nổ và chạm `api/webhook.py`/`agent/orchestrator.py` (đổi hành vi gửi/draft) — trái yêu cầu "không phá vỡ hiện tại".

---

## §2 — Goal

**VI:** `PendingReply` mang sẵn ba cột `snapshot`/`expires_at`/`label` (nullable, chưa cần backfill) để phần runtime sau ghi vào mà không migrate; `label` được set tất định mỗi lần duyệt/từ chối ngay từ bây giờ (nuôi §8). Một bảng `webhook_event_log` với PK `(channel, platform_msg_id)` + repo `record_event` on-conflict-do-nothing, chứng minh bằng test hai insert đồng thời chỉ ra một row. Zero đổi hành vi gửi khách / draft / gate.

**EN:** `PendingReply` carries three nullable columns (`snapshot`/`expires_at`/`label`) so the deferred runtime can write them without a data migration; `label` is set deterministically on every approve/reject now, feeding §8. A `webhook_event_log` table keyed `(channel, platform_msg_id)` with an on-conflict-do-nothing `record_event` repo, proven by a concurrent-insert test yielding exactly one row. No change to customer-send / draft / gate behavior.

---

## §3 — Scope

- `db/models.py` — `PendingReply` +3 cột · `WebhookEventLog` (model mới).
- `db/migrations/versions/0008_*.py` (draft schema) · `0009_*.py` (idempotency table) — số theo LAND order, xem PRE-1401.
- `db/repos.py` — `PendingReplyRepo.create(...)` nhận `snapshot`/`expires_at` optional; `mark_decided` set `label` từ `new_status` · `WebhookEventRepo(session)` mới với `record_event(...) -> bool`.
- `tests/test_draft_schema_idempotency.py` (mới).
- `docs/tasks/03-…` (Phase 2 → CANCELLED, CHỜ PRE-1403) · `docs/ROADMAP.md` (đóng vòng L3) · `docs/memory/KNOWN_ISSUES.md`.

### Out of scope (cố ý — đây là runtime, spec sau)

- ❌ **ACK-then-process + queue + worker drain** (`api/webhook.py`) — `GD0-INGEST` runtime.
- ❌ **Wire `record_event` vào webhook path** — cần signature-verify (`GD0-ZALO`, PRE-004) đứng trước.
- ❌ **Snapshot CAPTURE lúc draft** (`agent/orchestrator.py` + tier-1 tools) — cột nullable sẵn, ghi sau.
- ❌ **TTL computation `min(window, ngưỡng shop)` + cron expiry** — cột `expires_at` sẵn, tính sau.
- ❌ **Edit endpoint** (`label="edited"`) — cột nhận giá trị đó, đường ghi land khi có edit UI.
- ❌ **Đổi `HISTORY_MAX_MESSAGES` 20→6** — reconcile riêng (L1 v6 GD0-HISTORY), không trộn vào spec schema.

---

## §4 — Safety Gate Check (trục Ohana: safety → trust → stability → growth)

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Chỉ thêm cột nullable + bảng mới. Không đụng `shop_id` scope, không đụng đường gửi khách, không đụng `policy_gate`. `webhook_event_log` PK `(channel, platform_msg_id)` là **global** (platform_msg_id duy nhất theo channel toàn nền tảng) — `shop_id` lưu để audit, KHÔNG vào PK. ⚠️ `record_event` KHÔNG được nhận `shop_id` từ body chưa verify khi wire runtime — nhưng spec này chưa wire, chỉ dựng repo. | PASS |
| **User trust** | Cột `snapshot` là điều kiện tiên quyết để §2.5 phát hiện drift lúc duyệt — bảo vệ khách khỏi số cũ. Land cột trước khi có traffic = đúng chỗ. | PASS |
| **Stability** | Cột nullable ⇒ **không backfill**, test cũ xanh nguyên (fresh_db lấy schema từ `Base.metadata`). Migration reversible thật (drop column / drop table). | PASS |
| **Growth** | `label` từ ngày một mở khoá auto-send GĐ1 mà không phải tích data lại. | PASS |

**RED FLAG scan:**

- [x] **`label` KHÔNG được gộp vào `status`.** `status` là lifecycle gửi (`pending→approved→sent|rejected`); `label` là tín hiệu train (`approved|rejected|edited`). Chúng TRÙNG cho approve/reject nhưng LỆCH cho edited (seller sửa text rồi duyệt: `status=approved` nhưng `label=edited`). Gộp lại = mất tín hiệu `edited` mãi mãi. Cột riêng.
- [x] **`label` derive từ `new_status` trong repo, không để caller tự khai.** `api/inbox.py` không đổi — `mark_decided(new_status="approved")` tự set `label="approved"`. Caller tự truyền label = chỗ để một refactor sau ghi sai nhãn vào training set.
- [x] **`snapshot` là JSONB nullable, validate shape khi CAPTURE land (spec sau), không phải bây giờ.** Ghi cột rỗng giờ không cần Pydantic; nhưng đường ghi tương lai PHẢI validate lúc GHI (bài học spec 11 `knowledge`).
- [x] **Idempotency test PHẢI chạy trên Postgres thật, không SQLite.** `on_conflict_do_nothing` + PK compound là hành vi Postgres; conftest `fresh_db` dùng Postgres CI thật ⇒ test hai-insert-đồng-thời có giá trị. SQLite sẽ cho kết quả khác và test nói dối.
- [ ] ⚠️ **`webhook_event_log` là bảng append-only sẽ phình.** Chưa có retention/cleanup. Chấp nhận GĐ0 (0 traffic); ghi KNOWN_ISSUES để `GD3-HARDEN` (log retention) nhặt.

---

## §5 — Source files

Đọc TRƯỚC khi sửa: `db/models.py` (§PendingReply cho cột hiện có + §Conversation cho `window_status`/`last_inbound_at` — liên quan TTL sau) · `db/repos.py` (`PendingReplyRepo` §74–168, pattern `shop_scope`, `mark_decided`) · `db/migrations/versions/0007_shops_profile.py` (style migration mới nhất) · `channels/base.py` (shape `InboundMessage` — `channel` + id nguồn, để B0 biết key đến từ đâu khi wire sau) · `tests/conftest.py` (`fresh_db` lấy schema từ `Base.metadata`) · `api/inbox.py` (xác nhận `mark_decided` là call-site duy nhất — để set label ở repo là đủ) · `docs/backend-workflow.md` §2.1/§2.3/§2.5.

---

## §6 — PRE checks

```
PRE-1401: Số migration 0008/0009 — kiểm CẢ đĩa LẪN docs/tasks/ lúc execute.
  Trạng thái: ⚠️ VA CHẠM cùng loại spec 11 PRE-1103 (lần thứ NĂM).
    Trên đĩa mới nhất: 0007 (spec 11). docs/tasks/ (spec 03 BLOCKED) giữ chỗ 0008/0009.
    Spec 14 lấy 0008 (A0) + 0009 (B0) NẾU land trước spec 03 ⇒ spec 03 dịch tiếp.
  Command: ls db/migrations/versions/ && grep -rhoE '000[0-9]' docs/tasks/*.md | sort -u
  Luật: số cấp theo thứ tự LAND, không theo lập kế hoạch. Alembic nối bằng down_revision,
        không bằng số trong tên file. Xem [[project-spec03-datamodel-hole]].

PRE-1402: Row count pending_reply (quyết định RISK, KHÔNG quyết backfill).
  Trạng thái: ⏳ ĐO lúc execute. Cột thêm là NULLABLE ⇒ không cần backfill dù có row.
    Nhưng > 0 row nghĩa có traffic thật ⇒ cân nhắc nâng RISK A0 lên high.
  Command: (trên Postgres thật) SELECT count(*) FROM pending_reply;
  Kỳ vọng: 0 (spec 11 PRE-1104 đo 0 row 2026-07-20; xác nhận lại chưa đổi).

PRE-1403: Spec 03 Phase 2 sở hữu `webhook_event_log` — supersede? Wyatt chốt.
  Trạng thái: ⏳ CHỜ KÝ. Tiền lệ: spec 11 supersede 03 Phase 1 (Wyatt ký 2026-07-20).
    Phase 2 mang idempotency table, STATUS BLOCKED (chờ PRE-004 ở Tân). Nhưng phần
    BẢNG là internal — không cần PRE-004. ⇒ đề nghị spec 14 B0 bao phần schema,
    03 Phase 2 → CANCELLED (giữ dấu vết, không xoá). KHÔNG tự quyết.

PRE-1404: `label` derive-from-status bây giờ vs chờ edit path — Wyatt xác nhận.
  Trạng thái: ⏳ CHỜ. Đề xuất: set label={approved|rejected} theo new_status NGAY (đủ
    cho auto-send train 2 nhánh chính); `edited` reserve tới khi edit endpoint land.
    Rủi ro nếu chờ: mọi duyệt/từ chối GĐ0 không có label ⇒ đúng thứ §8.1 cảnh báo.
```

---

## §7 — Execute Steps

> Mỗi phase: RISK **đề xuất**, Wyatt ký. Floor rule: ALLOWED_FILES giao RISK_PATHS
> (`db/migrations`) ⇒ tối thiểu `medium`. Không đề xuất high: cột nullable + bảng mới,
> không backfill, không đổi hành vi gửi/tiền/gate (nâng high nếu PRE-1402 > 0 row).

### Phase A0 — `PendingReply` +snapshot/expires_at/label + label-on-decide

<!-- ADP:PHASE A0 -->
STATUS: DONE
EVIDENCE: commit=346ff46, gate_exit=0, duration=14s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=170cce9b177d,tier=medium), smoke=N/A(migration schema — không có service runtime người dùng quan sát; đúng-sai verify bằng alembic up→down→up trên Postgres thật (§10) + CI alembic step + test hai-insert trên Postgres CI thật.), ran=2026-07-21T18:20
ROADMAP: GD0-DRAFTSCHEMA
GOAL: `PendingReply` có 3 cột nullable `snapshot JSONB` / `expires_at TIMESTAMPTZ` / `label TEXT` (CHECK ∈ {approved,rejected,edited} hoặc NULL); `PendingReplyRepo.create` nhận `snapshot`/`expires_at` optional (default None — call-site cũ không đổi); `mark_decided(new_status="approved")` set `label="approved"`, `"rejected"`→`"rejected"`; migration up→down→up sạch trên Postgres thật; toàn bộ test cũ xanh nguyên (cột nullable).
APPROACH: ALTER thêm 3 cột nullable — không backfill (PRE-1402=0 row kỳ vọng). `label` derive TRONG `mark_decided` từ `new_status`, KHÔNG thêm tham số cho caller ⇒ `api/inbox.py` KHÔNG đổi (giữ blast radius = repo + schema). CHECK constraint ở DB cho `label` (Pydantic chưa cần vì chưa có đường ghi snapshot). `snapshot` để JSONB free-form GĐ này — shape sẽ pin khi capture land (spec runtime), validate-lúc-ghi lúc đó. Cột `expires_at` chỉ là chỗ chứa; tính `min(window, ngưỡng shop)` là runtime sau.
ALLOWED_FILES: db/models.py, db/migrations/versions/, db/repos.py, tests/test_draft_schema_idempotency.py, docs/tasks/14-Task-OhanaAISeller-DraftSchema-Idempotency.md, docs/reviews/, docs/smokes/
ALLOWED_FILES_AMEND: Wyatt duyệt 2026-07-21 (option 1) — 2 file thêm, KHÔNG phải mở scope tuỳ ý mà là gỡ nợ CHẶN GATE_FULL chung:
  · `agent/drafter.py` + `tests/test_drafter.py`: `ruff format --check` ĐỎ trên HEAD (`git show HEAD:agent/drafter.py | ruff format --check` xác nhận, ruff pin 0.15.22). Spec 13 D0/D1 (`dc282b4`/`77c60c1`) stamp DONE trong khi format đỏ — hình dạng ISSUE-019 (gate ký DONE lúc thực ra đỏ). `GATE_FULL` của A0 gồm `ruff format --check .` ⇒ không thể xanh tới khi 2 file này sạch. Fix = `ruff format` cơ học thuần, ZERO đổi hành vi (diff chỉ whitespace/wrap). Un-break gate cho mọi phase sau. Ghi ISSUE-025 (KNOWN_ISSUES ở C0).
GATE: .venv/bin/python -m pytest tests/test_draft_schema_idempotency.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (✅ WYATT KÝ 2026-07-21. Floor: `db/migrations`. Không high: cột nullable, PRE-1402=0 row, không backfill, không đổi hành vi gửi/gate.)
BLOCKED_BY: PRE-1401 ✅ (đĩa=0007⇒lấy 0008) · PRE-1402 ✅ (0 row) · PRE-1404 ✅ (label derive-from-status, edited reserved)
SMOKE: N/A migration schema — không có service runtime người dùng quan sát; đúng-sai verify bằng alembic up→down→up trên Postgres thật (§10) + CI alembic step + test hai-insert trên Postgres CI thật.
REVIEW: PASS ref=docs/reviews/14-A0-auto-verdict.json
<!-- /ADP -->

1. Test (**RED trước**): (a) 3 cột tồn tại + nullable; (b) `create()` không truyền snapshot/expires ⇒ hàng cũ vẫn tạo được (None); (c) `create()` có truyền ⇒ lưu đúng; (d) `mark_decided("approved")` ⇒ `label=="approved"`; `"rejected"`⇒`"rejected"`; (e) `label` giá trị ngoài CHECK bị DB từ chối; (f) migration up→down→up trên Postgres thật.
2. Model +3 cột + CHECK.
3. Migration `0008`.
4. Repo: `create` optional args + `mark_decided` set label.
5. **STOP+WAIT**.

### Phase B0 — `webhook_event_log` + `WebhookEventRepo.record_event`

<!-- ADP:PHASE B0 -->
STATUS: DONE
EVIDENCE: commit=3d7bf62, gate_exit=0, duration=14s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=976094c6bbff,tier=medium), smoke=N/A(migration schema — verify bằng alembic up→down→up + test hai-insert-đồng-thời trên Postgres CI thật (on_conflict là hành vi Postgres, SQLite sẽ nói dối).), ran=2026-07-21T18:30
ROADMAP: GD0-INGEST
GOAL: Bảng `webhook_event_log(channel TEXT, platform_msg_id TEXT, shop_id TEXT, received_at TIMESTAMPTZ)` PK `(channel, platform_msg_id)`; `WebhookEventRepo.record_event(channel, platform_msg_id, shop_id) -> bool` trả `True` lần đầu, `False` khi trùng (on_conflict_do_nothing + re-check); test HAI record_event đồng thời cùng key ⇒ đúng MỘT row, cái sau `False`; migration up→down→up sạch.
APPROACH: `on_conflict_do_nothing` trên PK compound — cùng cơ chế race-safe spec 09 dùng cho `Conversation` (KHÔNG select-then-insert; đó là ISSUE-017). `record_event` không scope `shop_id` vào PK: `platform_msg_id` đã duy nhất theo channel toàn nền tảng; `shop_id` lưu để audit + truy vết. Repo KHÔNG có `shop_scope` (khác các repo khác) vì idempotency là biên giới nền-tảng, không phải dữ liệu tenant — ghi rõ trong docstring để đừng ai "sửa" thành shop-scoped. **KHÔNG wire vào `api/webhook.py`** (đó là runtime `GD0-INGEST`, cần signature-verify PRE-004 đứng trước).
ALLOWED_FILES: db/models.py, db/migrations/versions/, db/repos.py, tests/test_draft_schema_idempotency.py, docs/tasks/14-Task-OhanaAISeller-DraftSchema-Idempotency.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_draft_schema_idempotency.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (✅ WYATT KÝ 2026-07-21 tại ANCHOR. Floor: `db/migrations`. Không high: bảng mới, không wire runtime, không đường gửi khách.)
BLOCKED_BY: A0 DONE ✅ · PRE-1401 ✅ (đĩa=0008⇒lấy 0009) · PRE-1403 ✅ (Wyatt ký supersede 03 Phase 2 2026-07-21)
SMOKE: N/A migration schema — verify bằng alembic up→down→up + test hai-insert-đồng-thời trên Postgres CI thật (on_conflict là hành vi Postgres, SQLite sẽ nói dối).
REVIEW: PASS ref=docs/reviews/14-B0-auto-verdict.json
<!-- /ADP -->

1. Test (**RED trước**): (a) `record_event` lần đầu ⇒ `True` + 1 row; (b) lần hai cùng key ⇒ `False` + vẫn 1 row; (c) hai key khác nhau ⇒ 2 row; (d) migration up→down→up.
2. Model `WebhookEventLog` + PK compound.
3. Migration `0009`.
4. `WebhookEventRepo.record_event`.
5. **STOP+WAIT**.

### Phase C0 — Đóng vòng: 03 Phase 2 CANCELLED + KNOWN_ISSUES + L3

<!-- ADP:PHASE C0 -->
STATUS: TODO
ROADMAP: GD0-INGEST
GOAL: `03:2` mang `STATUS: CANCELLED` + trỏ spec 14 (nếu PRE-1403 ký); L3 sinh lại không còn map `GD0-INGEST → 03:2`; KNOWN_ISSUES ghi 5 nợ runtime hoãn (ACK/queue/worker · snapshot capture · TTL cron · edit-path label · webhook_event_log retention).
APPROACH: `CANCELLED` không xoá (mất dấu vết vì sao từng có). L3 máy sinh — KHÔNG sửa tay. Ghi nợ runtime ra KNOWN_ISSUES để không trôi: schema đã sẵn nhưng chưa ai tiêu thụ, đúng hình dạng "persona chưa có Drafter" của spec 11.
ALLOWED_FILES: docs/tasks/03-Task-GD0-AcceptanceBackfill.md, docs/tasks/14-Task-OhanaAISeller-DraftSchema-Idempotency.md, docs/ROADMAP.md, docs/memory/KNOWN_ISSUES.md, docs/reviews/, docs/smokes/
GATE: bash .claude/tools/adp-roadmap.sh "$PWD"
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && bash .claude/tools/adp-roadmap.sh "$PWD"
RETRY: 0/3
RISK: low (ĐỀ XUẤT — Wyatt ký. ALLOWED_FILES toàn docs, KHÔNG giao RISK_PATHS ⇒ floor không kích hoạt. Diff docs-only máy verify.)
BLOCKED_BY: A0 DONE · B0 DONE · PRE-1403
SMOKE: N/A diff docs-only — không đổi dòng code; bằng chứng là L3 sinh lại (`GD0-INGEST`/`GD0-DRAFTSCHEMA` coverage), chính là GATE máy verify.
<!-- /ADP -->

1. `03:2` → `CANCELLED` + lý do + trỏ spec 14 (nếu PRE-1403 ký; nếu KHÔNG ký thì bỏ bước này, chỉ ghi KNOWN_ISSUES).
2. KNOWN_ISSUES: 5 nợ runtime.
3. Sinh lại L3.
4. **STOP+WAIT**.

---

## §8 — DB Changes

- **Alembic `0008` (A0):** `ALTER TABLE pending_reply ADD COLUMN snapshot JSONB NULL, ADD COLUMN expires_at TIMESTAMPTZ NULL, ADD COLUMN label TEXT NULL CHECK (label IN ('approved','rejected','edited'))`. `downgrade` drop 3 cột.
- **Alembic `0009` (B0):** `CREATE TABLE webhook_event_log (channel TEXT NOT NULL, platform_msg_id TEXT NOT NULL, shop_id TEXT NOT NULL, received_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (channel, platform_msg_id))`. `downgrade` drop table.
- Cột `snapshot`/`expires_at` để **nullable**: chưa có đường ghi ⇒ NOT NULL sẽ chặn mọi `create()` cũ. Khi capture land, cân nhắc default hoặc giữ nullable (draft gọi trực tiếp không qua webhook có thể không có snapshot).
- `webhook_event_log.shop_id` **KHÔNG** FK về `shops.id` — cùng lý do spec 11 PRE-1104 `embeddings._platform`: sentinel/pre-verify có thể chưa là shop thật. Lưu để audit, không ràng buộc.
- NEVER edit migration đã apply — thêm revision mới.

---

## §10 — Post-checks

```bash
.venv/bin/python -m pytest tests/ -q -m 'not live'
.venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth
.venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
alembic upgrade head && alembic downgrade -2 && alembic upgrade head   # trên Postgres THẬT (2 revision)
```

⚠️ **pytest xong thì schema alembic bẩn** — `fresh_db` drop/create từ `Base.metadata`, không đụng `alembic_version`. Verify chuỗi migration phải reset schema; nếu `drop schema public cascade` thì `CREATE EXTENSION vector` lại bằng superuser `drnick` (KHÔNG `postgres`). Xem `docs/smokes/10-H0.md` §4.

---

## §11 — Deliverables

`db/models.py` (+3 cột PendingReply, +`WebhookEventLog`) · `db/migrations/versions/0008_*.py` · `0009_*.py` · `db/repos.py` (+optional args `create`, +label trong `mark_decided`, +`WebhookEventRepo`) · `tests/test_draft_schema_idempotency.py` · `docs/tasks/03-…` (Phase 2 CANCELLED nếu ký) · `docs/ROADMAP.md` · `docs/memory/KNOWN_ISSUES.md`.

Commit: `adp/14-Task-OhanaAISeller-DraftSchema-Idempotency phase-<id>: checkpoint` (do `adp-checkpoint.sh` viết).

---

## §12 — Constraints

🚫 **KHÔNG wire `record_event` vào `api/webhook.py`** — runtime `GD0-INGEST`, cần signature-verify (PRE-004) đứng trước. Spec này chỉ dựng bảng + repo.
🚫 **KHÔNG capture snapshot lúc draft** ở spec này — chạm `agent/orchestrator.py` (đổi hành vi draft). Cột nullable sẵn, ghi sau.
🚫 **KHÔNG gộp `label` vào `status`** — hai khái niệm khác, `edited` sẽ mất.
🚫 **KHÔNG để caller truyền `label`** — derive trong repo từ `new_status`.
🚫 **KHÔNG NOT NULL cho snapshot/expires_at** — chặn mọi `create()` cũ.
🚫 **KHÔNG FK `webhook_event_log.shop_id` → `shops.id`** — sentinel/pre-verify chưa là shop.
🚫 **KHÔNG shop-scope `WebhookEventRepo`** — idempotency là biên giới nền-tảng, không phải dữ liệu tenant.
🚫 **KHÔNG test idempotency trên SQLite** — `on_conflict` là hành vi Postgres; conftest dùng Postgres CI thật.
🚫 **KHÔNG đổi `HISTORY_MAX_MESSAGES` 20→6 ở đây** — reconcile riêng.
🚫 Self-certify DONE ngoài `adp-checkpoint.sh`.

---

## §13 — Tracking

| Phase | Nội dung | STATUS | RISK (đề xuất) |
|---|---|---|---|
| A0 | `PendingReply` +snapshot/expires_at/label + label-on-decide | TODO | medium |
| B0 | `webhook_event_log` + `record_event` race-safe | TODO | medium |
| C0 | 03 Phase 2 CANCELLED + KNOWN_ISSUES + L3 | TODO | low |

---

## §14 — Open questions (Wyatt quyết — spec KHÔNG tự chốt)

**Q1 · PRE-1403 — supersede spec 03 Phase 2?** Bảng `webhook_event_log` là internal (không cần PRE-004). Đề nghị spec 14 B0 bao, `03:2` → CANCELLED. Tiền lệ: spec 11 supersede `03:1`. Nếu KHÔNG ký, B0 vẫn dựng bảng nhưng C0 bỏ bước CANCELLED.

**Q2 · RISK tiers.** Đề xuất A0=medium, B0=medium, C0=low. Nâng A0→high nếu PRE-1402 đo > 0 row (có traffic thật). Wyatt ký.

**Q3 · PRE-1404 — `label` derive-from-status ngay?** Đề xuất set {approved|rejected} theo `new_status` bây giờ, `edited` chờ edit endpoint. Hay chờ cả cụm tới khi có edit path (rủi ro: GĐ0 mất label)?

**Q4 · `snapshot` shape.** GĐ này JSONB free-form (chưa có đường ghi). Khi capture land, pin shape gì (giá/tồn/order-status tại T0)? Ghi để spec runtime không phải tự nghĩ lại.
