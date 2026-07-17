# 01-Task-OhanaAISeller-GD0

<!-- spec-generator v2.3 · Branch B (raw brief, no v3 marker) -->
<!-- PROJECT: Ohana AI Seller (greenfield fork ← DrNickv4). NOT ONFA wallet, NOT DrNick on-disk. -->
<!-- ADP:MANIFEST (proposed — Wyatt finalize)
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/chat.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder (reuse — Python/FastAPI Plan-Patch-Verify)
CHECKPOINT_PREFIX: adp
-->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ohana AI Seller — GĐ0 MVP (fork DrNickv4) |
| Parent | Ohana product roadmap (GĐ0 → acceptance gate → tranche 100M) |
| Depends-on | DrNickv4 @ main (source of ported modules) |
| Owner | R: Tân (dev lead) · A: Wyatt (fractional CTO, spec approval + RISK tier) |
| Branch | `main` (repo mới `ohana-ai`) |
| Duration (ước lượng thô) | 3–4 tuần, Zalo-only |
| Spec type | Full (14-section) |
| Workflow mode | IMPLEMENT |
| inherited_from | — (Branch B) |

> **Priority order (Ohana, thay cho fintech Survival Framework):** safety → user trust → stability → growth. §4 dùng bộ này, KHÔNG dùng LR/WP/TV/UR.

---

## §1 — Problem Statement

Ohana cần một AI copilot cho seller social-commerce VN (Zalo/FB/IG). Build from scratch một agent RAG + tool-calling + human-in-the-loop là công lớn và rủi ro. DrNickv4 đã có sẵn engine hardened (ReAct+Reflect orchestrator, pgvector RAG với namespace isolation, tool registry + dispatch, LLM adapter đa provider, guardrail + reviewer + CI + ADP discipline) nhưng single-tenant và gắn chặt financial (2FA, atomic money-state, ONFA REST).

**Cần:** tách phần engine generic của DrNick, bỏ phần financial/single-tenant, dựng lại **tenant-first** cho Ohana với 3 feature. Rủi ro chính: retrofit multi-tenancy lên code single-tenant = nhà máy đẻ bug rò dữ liệu chéo (loại R1.22).

**Evidence (đã audit on-disk DrNickv4 @ main):**
- `bridge/` chỉ 1 file `onfa_client.py` → integration surface đơn nhất, phải viết mới cho Zalo.
- `auth/` = identity.py + jwt.py + admin.py → JWT single-subject.
- `db/models.py` = 139 loc → **[UNVERIFIED]** chưa đọc body, chưa xác nhận có cột tenant/shop.
- `api/` chat-centric đồng bộ (SSE) → khớp F1/F2, KHÔNG khớp F3 async approve.

---

## §2 — Goal

**VI:** Ship GĐ0 MVP Ohana AI Seller trên 1 kênh (Zalo OA), gồm 3 feature: (1) tìm kiếm wiki nền tảng để trả lời khách, (2) nối API trả lời câu hỏi general của khách, (3) seller copilot draft reply — GĐ đầu seller duyệt manual, kiến trúc switchable sang auto. Tất cả qua **1 pipeline thống nhất + 1 policy gate risk-scored**.

**EN:** Ship a single-channel (Zalo OA) MVP of the Ohana AI seller copilot with wiki-RAG customer support, API-backed general Q&A, and human-in-the-loop reply drafting, all routed through one unified draft engine gated by a per-message risk policy.

---

## §3 — Scope

### Sub-task A — Repo bootstrap tenant-first (port chọn lọc)
- Port sang: `agent/llm_client.py` + `providers/`, `agent/embedder.py`, `retrieval/`, `parsing/`, `storage/`, `.claude/hooks/guardrail.py`, reviewer subagent, CI workflow, Alembic skeleton, RULES/ADP.
- Bỏ lại: `bridge/onfa_client.py`, `tools/onfa_actions.py` (money/2FA), `pending_action` financial logic, ConfirmEvent 2FA path.
- Files (repo mới): toàn bộ layout trên + `db/models.py` viết lại tenant-first.

### Sub-task B — Multi-tenancy foundation
- Mọi bảng có `shop_id` (+ `tenant_id`/`seller_id` theo mô hình). Row-level scope enforced.
- JWT claim mở rộng: `(user_id, shop_id, role)` verified — R1.1 mở rộng thành pair.
- `retrieval/`: namespace filter SQL-level phải include `shop_id` (F1 wiki = shared platform namespace; conversation = per-shop).
- Files: `auth/identity.py`, `db/models.py`, `db/migrations/`, `retrieval/*`.

### Sub-task C — Feature 1: Wiki RAG
- Admin ingest pipeline: upload wiki docs → `parsing/` chunk → `embedder` → pgvector namespace `platform_wiki`.
- Read-tool `search_wiki(query)` trong registry (kind=READ).
- Files: `parsing/*`, `retrieval/*`, `tools/wiki.py`, `api/admin.py` (ingest endpoint).

### Sub-task D — Feature 2: API Q&A tools
- `bridge/ohana_client.py` (REST client, verify=True, service token) — pattern port từ onfa_client.
- Read-tools: `order_status`, `shipping_info`, `product_info`, `account_lookup` (kind=READ) — **[UNVERIFIED]** danh sách API thật của nền tảng Ohana chưa có → PRE-002.
- Files: `bridge/ohana_client.py`, `tools/ohana_read.py`, `tools/registry.py`.

### Sub-task E — Feature 3: Seller copilot + unified pipeline + policy gate
- `api/webhook.py`: nhận Zalo OA webhook (message inbound) → enqueue.
- Draft engine: orchestrator sinh draft dùng F1+F2 làm context.
- `agent/policy_gate.py` (**NET-NEW, RISK path**): quyết định auto_send vs park.
  ```
  auto_send = confidence ≥ threshold
              AND intent ∉ {complaint, refund, price_negotiation, specific_order}
              AND shop.auto_enabled(intent)
  → else park pending_reply (seller duyệt async)
  ```
- `pending_reply` table (port shape từ `pending_action`, bỏ 2FA, thêm async status + ownership check S4 theo `shop_id`).
- Seller inbox UI: list pending → view draft → edit/approve/reject → send.
- Files: `api/webhook.py`, `agent/policy_gate.py`, `agent/orchestrator.py` (adapt), `db/models.py`, `web/` (inbox — reuse **[UNVERIFIED]**).

### Out of scope GĐ0
- FB/IG messaging (GĐ1 — cần Meta app review, bắt đầu song song sớm).
- RAG few-shot từ reply history seller (GĐ2).
- Financial AI (GĐ4, budget riêng, ngoài 600M).
- Auto-send mode bật thật cho F3 (chỉ dựng switchable, để threshold cao/off).

---

## §4 — Safety Gate Check (thay Survival Framework)

Ohana không phải wallet — không có LR/WP/TV/UR. Filter theo priority order: **safety → trust → stability → growth**.

| Trục | Đánh giá GĐ0 | Verdict |
|---|---|---|
| Safety | F1/F2 auto-send thẳng khách = không lưới người. Câu wiki/API sai → tới khách. **Bắt buộc** risk gate: confidence threshold + intent blocklist + fallback về manual. | ⚠️ FLAG — gate là điều kiện ship, không optional |
| User trust | Reply sai giá/tồn kho = mất trust + tiền thật của seller. Intent nhạy cảm (khiếu nại, hoàn tiền, mặc cả, đơn cụ thể) BẮT BUỘC qua seller kể cả auto mode. | ⚠️ FLAG — enforced trong policy_gate |
| Stability | Multi-tenancy retrofit = rủi ro rò chéo cao nhất. Namespace isolation SQL-level + reviewer check mỗi patch. Zalo OA rate limit (8 msg/48h reactive window) → cần cảnh báo seller trước hết window. | ⚠️ FLAG |
| Growth | Chỉ tính sau khi 3 trục trên đạt. Zalo-first (memory: recommended). | PASS (điều kiện) |

**RED FLAG scan:**
- [x] Auto-send tới khách không có confidence gate → **BLOCK nếu ship raw**. Mitigation: `policy_gate.py` bắt buộc GĐ0.
- [x] Multi-tenant data leak → mitigation: `shop_id` scope SQL-level + reviewer S10-analog.
- [ ] External API (Zalo) không fallback → cần retry/queue + degrade sang manual khi Zalo down.

**VERDICT: FLAG** — ship được nhưng `policy_gate.py` (risk-scored) và namespace isolation là **acceptance-blocking**, không phải nice-to-have.

---

## §5 — Source Files & Context (đọc trước khi action)

**DrNickv4 @ main (nguồn port — đọc để hiểu pattern):**
- `agent/orchestrator.py` (635 loc) — ReAct+Reflect, ConfirmEvent, streaming events. Adapt cho async gate.
- `tools/registry.py` (158 loc) — Tool dataclass (defs+schema+kind+handler), dispatch. Port nguyên shape.
- `tools/onfa_read.py` — pattern read-tool (map sang wiki + ohana_read).
- `bridge/onfa_client.py` — REST client pattern (verify=True, `call(method, user_id, params)` seam).
- `auth/identity.py` (58 loc) + `auth/jwt.py` — JWT verify → mở rộng claim.
- `db/models.py` — **đọc body trước** (PRE-001) để biết có scaffold tenant sẵn không.
- `DRNICK_RULES_FOR_CLAUDE.md` — port toàn bộ R1–R19 discipline sang RULES Ohana.
- `.claude/hooks/guardrail.py` — port DENY rules, đổi R1.13 money → intent-safety cho Ohana.

**Ohana-side (chưa tồn tại — cần cung cấp):**
- Wiki docs source — **[UNVERIFIED] PRE-003: đang ở đâu? (Notion / Drive / markdown)**.
- Ohana platform REST API spec — **[UNVERIFIED] PRE-002**.
- Zalo OA app credentials + webhook spec — **[UNVERIFIED] PRE-004**.

---

## §6 — Pre-flight Checks (binary VERIFY, không phải discovery)

```
PRE-001: DrNick db/models.py có scaffold multi-tenant sẵn không.
  Command: grep -n "shop_id\|tenant_id\|__tablename__" db/models.py   (trong repo DrNick)
  Expected: xác định các bảng + có/không cột scope.
  If fail (không có scope): thiết kế lại models tenant-first from scratch (Sub-task B).

PRE-002: Ohana platform API — danh sách endpoint cho F2.
  Command: nhận API doc từ Tân/nền tảng; list endpoints (order/shipping/product/account).
  Expected: ≥ tên + method + auth của mỗi read-tool cần.
  If fail: STOP F2 tool content — F1+F3 vẫn build được độc lập.

PRE-003: Wiki docs source location + format.
  Expected: path/URL + format (md/pdf/html) để scope parsing/ ingest.
  If fail: STOP F1 ingest — dựng pipeline với 1 doc mẫu, backfill sau.

PRE-004: Zalo OA — credentials + webhook contract + rate-limit thật.
  Expected: OA access token, webhook payload shape, 48h/8-msg window confirm.
  If fail: STOP F3 send-leg — build draft engine + inbox UI với mock sender trước.

PRE-005: Confirm channel đầu = Zalo OA (memory: recommended, chưa Wyatt lock).
  Expected: Wyatt xác nhận Zalo-first (không phải FB/Meta first).
  If fail: đổi bridge target ở Sub-task D/E.
```

---

## §7 — Execute Steps (atomic, one-concern, TDD gate RED trước impl)

### Phase 1 — Bootstrap repo + port engine (Sub-task A)
<!-- ADP:PHASE 1 -->
STATUS: DONE
EVIDENCE: commit=299f4c8, gate_exit=0, duration=0s, review=PASS(judge=APPROVE,model=output-evaluator@haiku,bound=50349fe23478,tier=medium), ran=2026-07-17T07:43
GOAL: Repo `ohana-ai` chạy được `uvicorn app.main:app`; llm_client + embedder + retrieval + parsing port sạch, test smoke pass; financial modules KHÔNG có mặt.
APPROACH: Copy module generic; strip import ONFA/money; giữ CI + guardrail + ADP. Reviewer subagent port kèm. Delegated to spec 02 (4 sub-phases 1.0/1.1/1.2/1.3 all DONE, tagged phase-1-bootstrap).
ALLOWED_FILES: agent/, retrieval/, parsing/, storage/, app/, tests/, .claude/, pyproject.toml, .python-version, .gitignore, .github/, alembic.ini, db/, docs/memory/, docs/reviews/, Dockerfile
GATE_FULL: .venv/bin/python -m pytest -q && .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/mypy app
REVIEW: PASS ref=docs/reviews/01-Task-OhanaAISeller-GD0-phase-1.json
RETRY: 0/3
RISK: medium (finalized Wyatt 2026-07-16 — chạm agent/ + .claude/hooks/ trong RISK_PATHS)
<!-- /ADP -->

1. Init repo, copy port-list module, xóa `bridge/onfa_*`, `tools/onfa_*`, financial pending logic.
2. `test_smoke.py` (RED trước): app khởi động + import không lỗi.
3. Port guardrail.py + reviewer + CI; đổi rule R1.13 money→intent-safety placeholder.
4. STOP+WAIT review.

### Phase 2 — Multi-tenancy foundation (Sub-task B) — RISK
<!-- ADP:PHASE 2 -->
STATUS: IN_PROGRESS
GOAL: JWT verify trả `(user_id, shop_id, role)`; mọi bảng có `shop_id`; retrieval namespace filter SQL-level include shop_id; adversarial test: hàng out-of-shop bị loại.
APPROACH: models tenant-first; Alembic 0001; auth/identity mở rộng claim; Retriever.search bắt buộc shop scope (no default).
ALLOWED_FILES: auth/, db/models.py, db/session.py, db/__init__.py, db/migrations/, retrieval/, tests/test_tenant_isolation.py, tests/conftest.py, docs/reviews/, docs/tasks/01-Task-OhanaAISeller-GD0.md
GATE_FULL: .venv/bin/python -m pytest tests/test_tenant_isolation.py -x -q
REVIEW: PASS ref=docs/reviews/01-Task-OhanaAISeller-GD0-phase-2.json human=docs/reviews/01-Task-OhanaAISeller-GD0-phase-2-human.md
RETRY: 0/3
RISK: high (finalized Wyatt 2026-07-16 — thay đổi auth + schema behavior; per-step confirm + human review artifact required)
<!-- /ADP -->

5. `test_tenant_isolation.py` (RED): query shop A không thấy row shop B (DB + vector).
6. models.py tenant-first + migration 0001.
7. auth claim mở rộng + verify.
8. Retriever bắt buộc `shop_id` namespace. STOP+WAIT (per-step confirm — RISK high).

### Phase 3 — Feature 1 Wiki RAG (Sub-task C)
<!-- ADP:PHASE 3 -->
STATUS: TODO
GOAL: Ingest 1 wiki doc → chunk → embed → `search_wiki(query)` trả kết quả đúng namespace platform_wiki.
APPROACH: parsing pipeline + admin ingest endpoint + read-tool trong registry.
ALLOWED_FILES: parsing/, retrieval/, tools/wiki.py, tools/registry.py, api/admin.py
GATE: pytest tests/test_wiki_rag.py -x -q
RETRY: 0/3
RISK: low (finalized Wyatt 2026-07-16 — additive Wiki RAG, no auth/schema mutation)
<!-- /ADP -->

9. `test_wiki_rag.py` (RED): ingest doc mẫu → query → hit.
10. parsing ingest + embed pipeline.
11. `search_wiki` tool + happy-path test (R9.2). STOP+WAIT.

### Phase 4 — Feature 2 API Q&A tools (Sub-task D)
<!-- ADP:PHASE 4 -->
STATUS: TODO
GOAL: `bridge/ohana_client.py` gọi được platform API (verify=True); ≥1 read-tool (order_status) trả shape `{success, data}`.
APPROACH: port REST client pattern; read-tools kind=READ; user_id/shop_id là handler arg riêng (R1.1).
ALLOWED_FILES: bridge/ohana_client.py, tools/ohana_read.py, tools/registry.py
GATE: pytest tests/test_ohana_tools.py -x -q
RETRY: 0/3
RISK: medium (finalized Wyatt 2026-07-16 — bridge/ overlap RISK_PATHS)
BLOCKED_BY: PRE-002
<!-- /ADP -->

12. `test_ohana_tools.py` (RED, mock API): order_status trả đúng shape.
13. ohana_client + read-tools + registry sync (R1.4 — update ALL sources). STOP+WAIT.

### Phase 5 — Feature 3 pipeline + policy gate (Sub-task E) — RISK
<!-- ADP:PHASE 5 -->
STATUS: TODO
GOAL: webhook inbound → draft (F1+F2 context) → policy_gate quyết định → auto_send HOẶC park pending_reply; seller approve async → send. Intent nhạy cảm luôn park kể cả auto.
APPROACH: orchestrator adapt async; policy_gate risk-scored; pending_reply shape (bỏ 2FA, ownership S4 theo shop_id); inbox UI.
ALLOWED_FILES: api/webhook.py, agent/policy_gate.py, agent/orchestrator.py, db/models.py, db/migrations/, web/
GATE: pytest tests/test_policy_gate.py -x -q
GATE_FULL: pytest tests/test_policy_gate.py tests/test_orchestrator.py tests/test_tenant_isolation.py -q
RETRY: 0/3
RISK: high (finalized Wyatt 2026-07-16 — draft→customer behavior + auto-send gate; per-step confirm + human review)
BLOCKED_BY: PRE-004
<!-- /ADP -->

14. `test_policy_gate.py` (RED): (a) confidence thấp → park; (b) intent=complaint → park kể cả auto_enabled; (c) confidence cao + safe intent + auto_enabled → send.
15. policy_gate.py.
16. pending_reply table + migration + ownership check.
17. webhook receiver + enqueue.
18. orchestrator wire draft engine.
19. inbox UI (view/edit/approve/reject/send). STOP+WAIT (per-step — RISK high).

---

## §8 — DB Changes

- `0001_initial` (Phase 2): tất cả bảng tenant-first, mọi bảng có `shop_id` (index). Bảng lõi: `shops`, `sellers`, `customers`, `conversations`, `messages`, `embeddings` (namespace + shop_id), `pending_reply`.
- `pending_reply`: `{reply_id, shop_id, conversation_id, customer_id, draft_text, intent, confidence, status(pending|approved|sent|rejected|expired), created_at, decided_by, decided_at}`. **Bỏ** `requires_2fa`, `error_code` financial.
- NEVER edit migration đã apply — thêm revision mới (R6 db pair).
- **[UNVERIFIED]** schema chính xác chờ PRE-001 (xem DrNick models có scaffold không).

---

## §9 — i18n Keys

- Reply draft + inbox UI: VI-first (khách + seller VN). Không hardcode string trong view — dùng cơ chế i18n (port `getMessage()`-analog hoặc FE i18n).
- Intent labels (complaint/refund/…) là **enum code**, không phải localized text — FE localize (R7.3 pattern).

---

## §10 — Post-checks

```
py_compile mọi file đổi
ruff check . && ruff format --check .
mypy app
pytest -q  (toàn bộ, không skip DB test — CI có Postgres service)
guardrail headless: python .claude/hooks/guardrail.py <changed files>
Reviewer subagent: chạy S-checklist adapt (S1 user_id+shop_id from auth; S10 namespace isolation include shop_id)
Manual: Zalo webhook → draft → park → seller approve → send (end-to-end 1 luồng)
```

---

## §11 — Deliverables

- Repo `ohana-ai` @ main, chạy được, CI green.
- 3 feature demo-able trên Zalo OA (hoặc mock nếu PRE-004 chưa xong).
- `policy_gate.py` + test 3 nhánh pass.
- Tenant isolation test (DB + vector) pass.
- Commit pattern: `adp/01-OhanaGD0 phase-N: <concern>`.

---

## §12 — Constraints (STOP conditions + anti-patterns)

- **STOP+WAIT** sau mỗi phase; per-step confirm cho Phase 2 & 5 (RISK high).
- Additive/verify-first — grep trước khi sửa module port.
- **Auto-send KHÔNG bao giờ bỏ qua policy_gate** — kể cả demo. Intent nhạy cảm luôn park.
- `user_id`/`shop_id`/`tier` CHỈ từ verified auth — không từ request body/webhook payload (R1.1 mở rộng).
- Namespace/vector query luôn include `shop_id` SQL-level — không post-filter (R1.22 analog).
- Một patch = một concern. Bug phụ phát hiện → ghi KNOWN UNCOVERED, không fix (R1.10).
- KHÔNG fork nguyên DrNick repo — port chọn lọc vào repo tenant-first mới.
- Verification Report (R8) bắt buộc mỗi phase — không self-certify.

---

## §13 — Tracking

| Phase | Concern | RISK (proposed) | STATUS | EVIDENCE |
|---|---|---|---|---|
| PRE | 001–005 pre-flight | — | TODO | — |
| 1 | Bootstrap + port engine | medium | TODO | — |
| 2 | Multi-tenancy foundation | high | TODO | — |
| 3 | F1 Wiki RAG | low | TODO | — |
| 4 | F2 API Q&A tools | medium | TODO | — |
| 5 | F3 pipeline + policy gate | high | TODO | — |

> RISK tier = **proposed**, Wyatt finalize ở spec approval (DEC-019 floor rule). EVIDENCE do adp-checkpoint.sh ghi, không phải spec author.

---

## Assumptions & Open (không bịa — cần Wyatt/Tân chốt)

1. Channel đầu = **Zalo OA** (PRE-005) — memory recommend, chưa lock.
2. Wiki docs source + format (PRE-003) — chưa biết ở đâu.
3. Ohana platform API endpoints (PRE-002) — chưa có spec.
4. Zalo OA credentials + webhook contract + rate-limit thật (PRE-004).
5. DrNick `db/models.py` có scaffold tenant sẵn không (PRE-001) — chưa đọc body.
6. Mô hình tenant: `shop_id` đủ hay cần cả `seller_id`/`tenant_id` (1 seller nhiều shop?) — cần Wyatt xác nhận cardinality.
