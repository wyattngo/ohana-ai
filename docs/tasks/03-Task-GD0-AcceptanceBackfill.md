# 03-Task-GD0-AcceptanceBackfill

<!-- spec-generator v2.3 · Branch A (inherited from brief-formatter v3, pipeline=FORMAL) -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. Priority order = safety→trust→stability→growth (KHÔNG dùng LR/WP/TV/UR). -->
<!-- SCOPE SOURCE OF TRUTH: /Users/wyattngo/Desktop/Ohana/Roadmap.md v3 §3.2 gap table + §3.3 phase table + §2 intent taxonomy + §8 AI-engineering. Nếu spec này conflict với Roadmap v3, Roadmap thắng. -->
<!-- ADP:MANIFEST inherited từ ohana-ai/CLAUDE.md §5:
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder (reuse — Python/FastAPI Plan-Patch-Verify)
CHECKPOINT_PREFIX: adp
-->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ohana AI Seller — GĐ0 Acceptance Backfill (10 phase) |
| Parent | Ohana AI product roadmap (GĐ0 milestone — acceptance gate) |
| Depends-on | Spec 01 (5/5 phase DONE, shipped surface = tenant-first foundation + mock Zalo/API) |
| Owner | R: Tân (dev lead) · A: Wyatt (fractional CTO, spec approval + RISK tier finalize) |
| Branch | `main` (repo `ohana-ai`) |
| Duration (ước lượng thô) | 4–5 tuần sau khi PRE-002/003/004 unblock |
| Spec type | Full (14-section, Inherited from brief v3 FORMAL) |
| Workflow mode | IMPLEMENT (Roadmap v3 §3.3 đã hoàn thành PLAN — 10 phase scope rõ) |
| inherited_from | brief-formatter-v3 (revised) + Roadmap.md v3 canonical |
| brief_pipeline | FORMAL |
| brief_timestamp | 2026-07-17 |
| brief_workflow_mode | IMPLEMENT |

> **Priority order (Ohana):** safety → user trust → stability → growth. §4 dùng bộ này, KHÔNG dùng LR/WP/TV/UR fintech Survival Framework.

---

## §1 — Problem Statement

Spec 01 shipped 5/5 phase với **mock** — tenant-first foundation + policy-gate + MockTransport Ohana REST + MockZaloSender. Gate-passed 100% ADP nhưng KHÔNG phải acceptance-DONE. 13 gap giữa spec-DONE và milestone-DONE của GĐ0 (Roadmap v3 §3.2):

**Production surface gap:**
- Zalo OA thật gửi/nhận E2E chưa hoạt động (`MockZaloSender`, webhook `enabled=False`)
- Không có `shops` table + JWT extension từ real onboard flow
- Không có `webhook_event_log` idempotency
- Không có Zalo 48h reactive window scheduler

**Data completeness gap:**
- Wiki corpus thật chưa ingest (Phase 3 pass qua inline fixture)
- F2 tools 2/3/4 (`shipping_info`, `product_info`, `account_lookup`) chưa build (Phase 4 chỉ ship `order_status` với MockTransport)

**AI-layer gap (lỗ hổng lớn nhất — Roadmap v3 §3.2):**
- **Không có eval harness** — prompt/model/RAG thay đổi silent regression, không có gate CI
- **Không có tool-call correctness + param validation** — tool hallucination risk
- **Không có intent classifier** — spam suggest = tốn credit, không route theo loại (Roadmap §2 15 loại)
- **Không có confidence-gated escalation** — AI overconfident draft sai + seller duyệt vội = thảm họa im lặng (failure mode chết người per Roadmap §8.4)
- **Không có model routing abstraction** — hardcode 1 model, PLANS advertise 3 tier = false promise
- **Không có LLM observability** — chỉ latency, thiếu token/cost/tool-success/RAG-hit/override + trace correlation

**Billing surface gap:**
- Không có credit metering server-side — bypass = business model leak
- Không có per-shop rate-limit — 1 tenant cost blowout

**Architecture gap:**
- Không có hosting region ADR — data residency + LLM provider data-flow chưa quyết định

**Evidence (audit on-disk 2026-07-17):**
- `bridge/zalo_sender.py` = `MockZaloSender` (logs, không call Zalo)
- `api/webhook.py` = scaffold với `enabled=False` default
- `tools/ohana_read.py` chỉ có `order_status` (không có shipping/product/account)
- `tools/wiki.py` + `api/admin.py` ingest ready, nhưng Phase 3 chạy inline text fixture
- Không có `agent/model_router.py`, `agent/intent_classifier.py`, `agent/eval/`, `agent/metering.py`
- Không có file eval golden set, không có OTel instrumentation

---

## §2 — Goal

**VI:** Ship Spec 03 — GĐ0 Acceptance Backfill 10 phase để đóng 13 gap giữa spec 01 spec-DONE và acceptance-DONE của GĐ0 milestone. Scope gồm **AI-layer hardening** (eval harness + grounding + tool-call correctness + intent classifier + confidence-gated escalation + LLM observability + model routing) + **production surface** (real Zalo E2E + credit metering per-lượt + per-shop rate-limit + 48h reactive window scheduler + shops+JWT real onboard) + **data completeness** (real wiki corpus + F2 tool coverage 2/3/4). Sau spec này, pilot 3–5 shop thật có thể chạy được, latency p95 <5s đo được, credit metering không bypass, intent nhạy cảm luôn escalate.

**EN:** Ship Spec 03 — GD0 Acceptance Backfill (10 phases) to close 13 gaps between spec 01 spec-DONE and GD0 acceptance-DONE. Covers AI-layer hardening (eval harness, hard grounding, tool-call correctness, intent classifier, confidence-gated escalation, LLM observability, model routing), production surface (real Zalo E2E, per-conversation credit metering, per-shop rate-limit, 48h reactive-window scheduler, shops+JWT real onboard), and data completeness (real wiki corpus, F2 tool coverage 2/3/4). Post-spec: 3–5 real shop pilots run, p95 latency measurable, credit metering non-bypassable, sensitive intents always escalate.

---

## §3 — Scope

### Sub-task A — Production surface (Phase 1, 2, 10)
- `shops` table + real onboard flow + JWT extension include `shop_id` từ verified auth (không stub).
- Real `ZaloSender` wire Zalo Send API + webhook signature verify + `webhook_event_log` idempotency.
- Zalo 48h reactive window scheduler + seller notification trước hết window.
- Files: `db/models.py` (add `Shop`, `WebhookEventLog`), `db/migrations/0004_*.py`, `auth/identity.py`, `bridge/zalo_sender.py`, `api/webhook.py`, `api/admin.py`, `agent/scheduler.py` (new).

### Sub-task B — Data completeness (Phase 3, 4)
- Real Wiki corpus batch ingest + delta ingest + admin UI upload (multipart).
- F2 tools 2/3/4: `shipping_info(order_id)`, `product_info(product_id)`, `account_lookup(customer_id)` với contract test.
- Files: `parsing/{chunk,ingest}.py` (extend), `api/admin.py`, `bridge/ohana_client.py`, `tools/ohana_read.py`, `tools/registry.py`.

### Sub-task C — Billing + rate-limit (Phase 5)
- `credit_ledger` table tenant-scope + middleware trừ credit per-lượt (KHÔNG token-based per Roadmap §3.2).
- Per-shop rate-limit (kéo về GĐ0 per Roadmap §3.2 — không đợi GĐ3).
- Bypass test (call API trực tiếp với body giả, verify không được).
- Files: `db/models.py` (add `CreditLedger`), `db/migrations/0006_*.py`, `agent/metering.py` (new), `api/middleware.py` (new).

### Sub-task D — AI-layer hardening (Phase 6, 7, 8, 9)
- **Eval harness** (Phase 6): golden fixtures + multi-dim assertion (structural/grounding/action-correctness/tone/safety) + rule-based + LLM-as-Judge + Manual Override Rate baseline + regression gate CI. Coverage matrix ≥ N golden case per intent family (Roadmap §2).
- **Model router** (Phase 7): `agent/model_router.py` plan_tier → model_id. Orchestrator gọi router, KHÔNG hardcode. Credit tính theo model tier (internal).
- **Intent classifier + confidence-gated escalation** (Phase 8): classifier route 15 loại intent (Roadmap §2). Escalation triggers: query ngoài catalog + tranh chấp/hoàn/khiếu nại (nhóm 12-13) + tone giận + đa nghĩa cao → không draft, hiện "cần bạn tự trả lời" + tóm tắt.
- **LLM observability** (Phase 9): OTel span quanh `orchestrator.step` với `token_in/out`, `cost`, `model_id`, `tool_calls[]` (+success/fail), `rag_hit`, `fallback_triggered`, `latency_ms`, `override`. Trace correlation (conversation ID xuyên suốt). Cost attribution per shop/plan. Latency p95 gate <5s.
- Files: `agent/eval/{__init__,golden,harness,judge,structural,grounding,action,tone,safety}.py`, `agent/model_router.py`, `agent/intent_classifier.py`, `agent/escalation.py`, `agent/orchestrator.py` (extend), `agent/observability.py` (new), `agent/policy_gate.py` (extend for escalation).

### Out of scope Spec 03
- FB Messenger + đa kênh abstraction (GĐ2 Spec 05a-b).
- Semantic product discovery / product RAG (GĐ2 Spec 05f).
- Payment integration (GĐ1 Spec 04b).
- Shipping integration (GĐ1 Spec 04c).
- Recurring billing subscription (GĐ3 Spec 06b).
- Reseller model (GĐ3 Spec 06c).
- External security audit (GĐ3 Spec 06f).
- Multi-provider LLM (defer GĐ3+ per Roadmap §1.2.12 — chỉ nếu uptime data chứng minh cần).
- Dynamic complexity routing (per Roadmap §8.2 — plan-tier trước, đo, rồi mới tính).
- Online eval sampling production (per Roadmap §8.1 — hook land nhưng chạy sau pilot, không GĐ0).

---

## §4 — Safety Gate Check (Ohana axes, KHÔNG dùng LR/WP/TV/UR)

Ohana priority order: **safety → user trust → stability → growth**. Filter theo Roadmap v3 §1.3 Guardrails table (AI KHÔNG được tự quyết payment-confirm/discount/refund/auto-send).

| Trục | Đánh giá Spec 03 | Verdict |
|---|---|---|
| **Safety** | 4 phase RISK-adjacent (Phase 1 auth, Phase 2 send-leg, Phase 5 metering, Phase 8 escalation). Phase 8 escalation là mitigation #1 cho "AI overconfident sai" (failure mode chết người per Roadmap §8.4). Phase 6 eval harness = regression gate, chặn silent degradation. **Guardrail §1.3 enforcement:** payment-confirm CHỈ qua webhook GĐ1 (không land ở Spec 03, nhưng escalation trigger phải include "khách nói ck rồi" → không auto). Discount/refund/hoàn → auto escalate. | ⚠️ FLAG — Phase 6+8 là acceptance-blocking, không optional |
| **User trust** | Reply sai giá/tồn kho → mất tiền seller. Phase 8 escalation cover nhóm intent 12-13 (đổi/trả + khiếu nại) — luôn escalate, không auto-draft. Manual Override Rate baseline (Phase 6+9) đo trust từ ground-truth seller. | ⚠️ FLAG — enforced trong intent classifier + escalation |
| **Stability** | Phase 2 real send-leg + idempotency chống retry duplicate. Phase 5 credit metering + rate-limit chống 1 tenant cost blowout. Phase 7 model router giải quyết false-promise 3 tier. Phase 9 observability = base cho SLO. Hosting region ADR (PRE-007) chốt data-flow trước ship. | ⚠️ FLAG — PRE-007 ADR bắt buộc trước Phase 1 execute |
| **Growth** | Không mở scope mới. Đóng gap để pilot 3–5 shop thật chạy được — điều kiện cho growth GĐ1+. | PASS (điều kiện) |

**RED FLAG scan (Roadmap §1.3 Guardrails):**
- [x] Auto-send bypass policy-gate → **BLOCK nếu ship**. Mitigation: policy-gate hardened Phase 8 + escalation triggers.
- [x] AI xác nhận "đã thanh toán" từ tin khách → **BLOCK**. Mitigation: escalation trigger include payment intent (không land payment webhook Spec 03, nhưng classifier phải route intent 10 → escalate, không draft "cảm ơn đã thanh toán").
- [x] AI freelance discount/hứa hoàn → **BLOCK**. Mitigation: escalation nhóm intent 12 luôn escalate.
- [x] Multi-tenant data leak (R1.22 analog) → mitigation: `shop_scope=` SQL-level đã enforce Phase 2 spec 01. Phase 5 `credit_ledger` + Phase 6 eval golden + Phase 9 trace correlation phải include `shop_id` scope check.
- [x] External API (Zalo/LLM) không fallback → cần retry/queue + degrade heuristic fallback (Roadmap §1.2.12). Phase 9 observability track `fallback_triggered`.
- [x] Fact hallucination (bịa stock/giá) → Phase 6 grounding assertion (rule-based).
- [x] Tool hallucination (gọi tool sai/param sai) → Phase 6 action-correctness + param validation trước execute.

**VERDICT: FLAG** — ship được nhưng Phase 6 (eval harness) + Phase 8 (escalation) + PRE-007 (hosting region ADR) là **acceptance-blocking**. Không có eval → không thể verify quality regression. Không có escalation → AI overconfident = thảm họa. Không có hosting ADR → data-flow qua LLM provider chưa quyết = compliance risk.

---

## §5 — Source Files & Context (đọc trước khi action)

**Spec 01 shipped surface (Ohana on-disk, edit-target hoặc reference):**
- `agent/orchestrator.py` — draft engine hiện tại, Phase 7 extend router hook + Phase 8 wire escalation + Phase 9 wire OTel span.
- `agent/policy_gate.py` — hiện chỉ decision auto_send vs park. Phase 8 extend include escalation triggers.
- `agent/embedder.py` + `agent/llm_client.py` + `providers/` — Phase 6 eval judge dùng.
- `retrieval/pgvector.py` — `PgvectorRetriever(shop_scope=)` SQL-level đã hard-filter. Phase 3 real corpus dùng cùng shape, KHÔNG modify.
- `parsing/{chunk,ingest,extract}.py` — Phase 3 extend cho batch + delta ingest.
- `bridge/ohana_client.py` — Phase 4 extend cho 3 endpoint mới (shipping/product/account). MockTransport pattern giữ nguyên cho contract test.
- `bridge/zalo_sender.py` — Phase 2 REPLACE `MockZaloSender` bằng `RealZaloSender`. Interface giữ nguyên (contract stable).
- `tools/ohana_read.py` — Phase 4 add 3 tool handler.
- `tools/registry.py` — Phase 4 register 3 tool mới.
- `tools/wiki.py` — Phase 3 không modify (search interface đã stable), corpus land qua ingest.
- `api/webhook.py` — Phase 2 enable signature verify + idempotency wrapper.
- `api/admin.py` — Phase 3 extend upload endpoint.
- `api/inbox.py` — Phase 8 UI hint để seller thấy "cần bạn tự trả lời" khi escalate.
- `auth/identity.py` — Phase 1 mở rộng claim source từ real onboard flow (không stub).
- `db/models.py` — Phase 1 (Shop, WebhookEventLog), Phase 5 (CreditLedger).
- `db/migrations/` — ~~Phase 1 (**0004**), Phase 2 (**0005**), Phase 5 (**0006**)~~ ⚠️ **SỐ NÀY ĐÃ CŨ (2026-07-19).**
  Spec 08 (EmbedderSwap-E5) chạy TRƯỚC spec này (spec 03 đang BLOCKED chờ Tân) và lấy **0004**.
  ⇒ Khi execute spec này, dịch thành **Phase 1 = 0005 · Phase 2 = 0006 · Phase 5 = 0007**.
  **Luật:** số migration cấp theo THỨ TỰ LAND, không theo thứ tự lập kế hoạch — Alembic nối
  chuỗi bằng `down_revision`, không bằng số trong tên file. Chạy lại `ls db/migrations/versions/`
  + `grep -rhoE '0[0-9]{3}' docs/tasks/*.md` trước khi đặt tên; **đừng tin số ghi sẵn ở đây**.
  Phase 10 KHÔNG còn cần migration (xem §8).

**DrNickv4 pattern (đọc để hiểu, KHÔNG edit):**
- `drnickv4/agent/orchestrator.py` — ReAct+Reflect pattern, ConfirmEvent shape (Phase 7 router hook lấy cảm hứng từ đâu).
- `drnickv4/bridge/onfa_client.py` — REST client pattern (verify=True, error handling) — Phase 4 3 tool mới follow cùng shape.
- `drnickv4/.claude/hooks/guardrail.py` — Phase 8 escalation triggers có thể tham khảo intent classification pattern.

**Reference documents:**
- **[CANONICAL] Scope:** [`/Users/wyattngo/Desktop/Ohana/Roadmap.md`](/Users/wyattngo/Desktop/Ohana/Roadmap.md) v3 — §3.2 gap + §3.3 phase + §2 intent taxonomy + §8 AI-eng chi tiết + §1.3 guardrails + §1.2 AI-layer discipline.
- [Spec 01](01-Task-OhanaAISeller-GD0.md) §6 — PRE-001..006 status (PRE-001/005/006 RESOLVED, PRE-002/003/004 BLOCKING backfill).
- [Ohana CLAUDE.md](../../CLAUDE.md) §5 — ADP:MANIFEST, RISK_PATHS, GATE_RUNNER.
- [Workspace CLAUDE.md](../../../CLAUDE.md) §4.7 — ADP v2.3 protocol (Ohana isolated).

**External docs (chờ Tân/Wyatt giao trước phase execute):**
- Ohana platform REST API spec — **[UNVERIFIED] PRE-002** (block Phase 4).
- Real wiki docs corpus + format — **[UNVERIFIED] PRE-003** (block Phase 3).
- Zalo Send API creds + webhook signature spec + rate-limit spec — **[UNVERIFIED] PRE-004** (block Phase 2 + Phase 10).
- Hosting region ADR — **[UNVERIFIED] PRE-007** (block Phase 1, phải viết trước).
- Credit metering pricing model per-lượt cụ thể — **[UNVERIFIED] PRE-008** (block Phase 5).
- Golden set size threshold N per intent + regression pass-rate threshold — **[UNVERIFIED] PRE-009** (block Phase 6).

---

## §6 — Pre-flight Checks (binary VERIFY, không phải discovery)

```
PRE-002: Ohana platform REST API — endpoint list cho F2 tools 2/3/4.
  Command: nhận API doc từ Tân/nền tảng; list ≥ 3 endpoint: shipping_info(order_id),
           product_info(product_id), account_lookup(customer_id) — mỗi cái có
           tên + method + auth + response shape.
  Expected: markdown/OpenAPI spec đủ để viết MockTransport contract test.
  If fail: STOP Phase 4 impl; Phase 4 CHỈ block, không dựng stub content.

PRE-003: Real Wiki docs corpus + format + pilot fixtures cho eval.
  Command: nhận từ Tân — (a) path/URL corpus (Notion export? Markdown repo? Google Docs?),
           (b) format (md/pdf/html), (c) sample size (ước lượng doc count),
           (d) ≥ 20 real conversation pilot đã anonymize cho eval golden set.
  Expected: source location + format + ≥1 sample doc + ≥20 sample conv.
  If fail: STOP Phase 3 real corpus ingest + Phase 6 golden fixtures; Phase 3 giữ
           inline fixture spec 01, Phase 6 chỉ dựng harness shape không content.

PRE-004: Zalo OA creds + webhook signature + rate-limit spec.
  Command: nhận từ Tân — (a) OA access token (staging + prod separate), (b) webhook
           signature algorithm + secret, (c) 48h/8-msg reactive window confirm,
           (d) rate-limit thật (req/s, req/day per OA).
  Expected: token + sig algorithm + rate spec đủ để wire RealZaloSender + scheduler.
  If fail: STOP Phase 2 real send + Phase 10 scheduler; Phase 2 giữ mock, Phase 10 defer.

PRE-007: Hosting region ADR (kiến trúc decision, KHÔNG paperwork).
  Command: viết ADR tại `docs/adr/YYYY-MM-DD-hosting-region.md` cover: (a) region
           lựa chọn (VN Vietel Cloud? Singapore? US?), (b) data-flow qua LLM provider
           (Anthropic/OpenAI endpoint region), (c) PDPD 13/2023 compliance path,
           (d) pgvector DB location + backup region.
  Expected: ADR file ACCEPTED bởi Wyatt trước Phase 1 execute.
  If fail: BLOCK toàn spec — data residency là kiến trúc constraint, không được vá sau.

PRE-008: Credit metering pricing model per-lượt cụ thể.
  Command: Wyatt/business chốt — (a) 1 credit / draft? / duyệt-gửi thành công?
           / theo intent complexity? (b) chu kỳ reset (daily/monthly?), (c) plan tier
           mapping (Free X credit/tháng, Normal Y, Pro Z).
  Expected: 1 dòng spec business rule đủ để viết `agent/metering.py`.
  If fail: STOP Phase 5; token-based accounting internal vẫn dựng được nhưng
           seller-facing metering block.

PRE-009: Golden set size + regression threshold cho eval gate CI.
  Command: Tân/Wyatt chốt — (a) N per intent family (Roadmap §2, 15 loại) — ước lượng
           tối thiểu 3-5 case/loại → tổng 45-75 case?, (b) regression pass-rate threshold
           (ví dụ 90% cho structural, 85% cho grounding, 75% cho tone).
  Expected: N + threshold đủ để write CI gate `.github/workflows/eval.yml`.
  If fail: Phase 6 dựng harness shape nhưng gate CI defer, block regression enforcement.

PRE-002/003/004 = inherited từ spec 01 (BLOCKING backfill status).
PRE-007/008/009 = NEW cho Spec 03.
```

---

## §7 — Execute Steps (atomic, one-concern, TDD gate RED trước impl)

### Phase 1 — shops table + JWT extension từ real onboard flow
<!-- ADP:PHASE 1 -->
STATUS: TODO
GOAL: `shops` table tồn tại; onboard flow tạo real shop → JWT include `shop_id` từ verified DB record; test: JWT của shop A không đọc được data shop B (cross-shop rejection).
APPROACH: Add `Shop` model + Alembic 0004; extend `auth/identity.py` load `shop_id` từ DB thay stub; onboard endpoint `POST /api/admin/shops` (admin auth); JWT issuance include `shop_id` claim; adversarial test cross-shop.
ALLOWED_FILES: db/models.py, db/migrations/0004_shops.py, auth/identity.py, api/admin.py, tests/test_shops_onboard.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_shops_onboard.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_shops_onboard.py tests/test_tenant_isolation.py -x -q
RETRY: 0/3
RISK: high (proposed, pending Wyatt sign — chạm auth/ + db/migrations trong RISK_PATHS; floor rule)
BLOCKED_BY: PRE-007 (hosting region ADR phải ACCEPTED trước)
<!-- /ADP -->

1. `test_shops_onboard.py` (RED): (a) POST /api/admin/shops tạo Shop record; (b) JWT include `shop_id` từ DB; (c) cross-shop rejection (shop A token không list shop B messages).
2. Add `Shop` model + Alembic 0004 (columns: id, name, zalo_oa_id UNIQUE, plan_tier, created_at, is_active).
3. Extend `auth/identity.py`: load shop_id từ `shops` table thay stub, verify is_active.
4. Add `POST /api/admin/shops` endpoint (admin-only auth).
5. STOP+WAIT (per-step confirm — RISK high).

### Phase 2 — Real ZaloSender + webhook signature + idempotency
<!-- ADP:PHASE 2 -->
STATUS: BLOCKED
GOAL: `RealZaloSender` gọi được Zalo Send API thật (staging OA); webhook inbound có signature verify; retry cùng event_id → duplicate rejected (idempotency).
APPROACH: Replace `MockZaloSender` bằng `RealZaloSender` (interface stable); wire httpx client với retry + timeout; `WebhookEventLog` table + middleware verify signature + dedup theo event_id; contract test qua httpx.MockTransport (không call Zalo staging thật trong CI, verify shape).
ALLOWED_FILES: bridge/zalo_sender.py, api/webhook.py, api/middleware.py, db/models.py, db/migrations/0005_webhook_log.py, tests/test_zalo_sender.py, tests/test_webhook_idempotency.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_zalo_sender.py tests/test_webhook_idempotency.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_zalo_sender.py tests/test_webhook_idempotency.py tests/test_orchestrator.py tests/test_tenant_isolation.py -x -q
RETRY: 0/3
RISK: high (proposed, pending Wyatt sign — bridge/ + api/webhook.py trong RISK_PATHS; production surface user-facing)
BLOCKED_BY: PRE-004 (Zalo creds + signature spec + rate-limit)
<!-- /ADP -->

6. `test_zalo_sender.py` (RED, MockTransport): (a) send message trả success shape; (b) retry on 5xx; (c) rate-limit 429 back-off.
7. `test_webhook_idempotency.py` (RED): (a) valid signature accepted; (b) invalid signature rejected 401; (c) duplicate event_id rejected 200 (idempotent no-op).
8. `RealZaloSender` implement (httpx + retry + timeout).
9. `WebhookEventLog` model + Alembic 0005.
10. Signature verify middleware + dedup wrapper trong `api/webhook.py`.
11. STOP+WAIT (per-step confirm — RISK high, user-facing production).

### Phase 3 — Real Wiki corpus ingest (batch + delta) + admin UI
<!-- ADP:PHASE 3 -->
STATUS: BLOCKED
GOAL: Batch ingest N doc thật từ PRE-003 source → chunk → embed → pgvector `platform_wiki` namespace; delta ingest re-run không duplicate; `search_wiki(query)` trả kết quả grounded (≥1 hit từ corpus thật).
APPROACH: Extend `parsing/chunk.py` cho batch mode; extend `parsing/ingest.py` với dedup theo doc_hash + delta detection; extend `api/admin.py` với multipart upload endpoint; giữ `search_wiki` tool + `PgvectorRetriever` interface không đổi (contract stable từ spec 01 Phase 3).
ALLOWED_FILES: parsing/chunk.py, parsing/ingest.py, parsing/extract.py, api/admin.py, tests/test_wiki_batch_ingest.py, tests/test_wiki_delta.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_wiki_batch_ingest.py tests/test_wiki_delta.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_wiki_batch_ingest.py tests/test_wiki_delta.py tests/test_wiki_rag.py -x -q
RETRY: 0/3
RISK: medium (proposed, pending Wyatt sign — parsing/ không trong RISK_PATHS nhưng api/admin.py có; PRE-003 unresolved block content)
BLOCKED_BY: PRE-003 (real wiki corpus source + format + pilot fixtures)
<!-- /ADP -->

12. `test_wiki_batch_ingest.py` (RED): batch 5+ doc → tất cả indexed, không duplicate chunk.
13. `test_wiki_delta.py` (RED): re-ingest same doc (hash không đổi) → skip; re-ingest changed doc → replace old chunks.
14. Extend `parsing/ingest.py` với `doc_hash` dedup + delta detection.
15. Extend `api/admin.py` multipart upload endpoint (admin auth).
16. STOP+WAIT.

### Phase 4 — F2 tools 2/3/4 (shipping_info, product_info, account_lookup)
<!-- ADP:PHASE 4 -->
STATUS: BLOCKED
GOAL: 3 read-tool mới trong registry: `shipping_info(order_id)`, `product_info(product_id)`, `account_lookup(customer_id)`. Contract test qua MockTransport khớp shape PRE-002. Tool-call qua orchestrator sinh param đúng schema (validated trước execute).
APPROACH: Extend `bridge/ohana_client.py` với 3 method mới (verify=True, retry); `tools/ohana_read.py` add 3 handler kind=READ; `tools/registry.py` register (R1.4 update ALL sources); param validation schema trước execute (guard tool hallucination).
ALLOWED_FILES: bridge/ohana_client.py, tools/ohana_read.py, tools/registry.py, tests/test_f2_tools.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_f2_tools.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_f2_tools.py tests/test_ohana_tools.py -x -q
RETRY: 0/3
RISK: medium (proposed, pending Wyatt sign — bridge/ + tools/registry.py trong RISK_PATHS; contract-shape gate closes với mock)
BLOCKED_BY: PRE-002 (Ohana REST endpoint list)
<!-- /ADP -->

17. `test_f2_tools.py` (RED, MockTransport): 3 tool đều trả `{success, data}` shape khớp PRE-002.
18. `bridge/ohana_client.py` add 3 method (shipping/product/account).
19. `tools/ohana_read.py` add 3 handler kind=READ + param validation schema (Pydantic).
20. `tools/registry.py` register 3 tool mới.
21. STOP+WAIT.

### Phase 5 — Credit metering + per-shop rate-limit
<!-- ADP:PHASE 5 -->
STATUS: TODO
GOAL: `credit_ledger` table tenant-scope; middleware trừ credit per-lượt theo PRE-008 rule; per-shop rate-limit chặn abuse; bypass test call API trực tiếp với body giả không lách được.
APPROACH: Add `CreditLedger` model + Alembic 0006; `agent/metering.py` implement debit + balance check; metering hook tại **biên orchestrator** (không có chat endpoint để wrap — xem bước 23) + rate-limit **Redis-backed BẮT BUỘC** (in-memory chỉ đúng khi 1 worker; nhiều uvicorn worker → đếm sai, chặn sai); adversarial bypass test.
ALLOWED_FILES: db/models.py, db/migrations/0006_credit_ledger.py, agent/metering.py, api/middleware.py, api/inbox.py, tests/test_credit_metering.py, tests/test_metering_bypass.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_credit_metering.py tests/test_metering_bypass.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_credit_metering.py tests/test_metering_bypass.py tests/test_tenant_isolation.py -x -q
RETRY: 0/3
RISK: high (proposed, pending Wyatt sign — billing surface, bypass = business model leak)
BLOCKED_BY: PRE-008 (credit pricing model per-lượt cụ thể)
<!-- /ADP -->

22. `test_credit_metering.py` (RED): (a) draft consume 1 credit; (b) balance = 0 → 402 Payment Required; (c) audit log entry per debit.
23. `test_metering_bypass.py` (RED, adversarial): **⚠️ `/api/chat/draft` KHÔNG TỒN TẠI** — không có endpoint draft nào; draft chạy trong `agent/orchestrator.py`, kích bởi `api/webhook.py` (chưa mount). Metering phải hook **biên orchestrator**, KHÔNG phải HTTP middleware. Test: gọi qua surface thật (webhook khi đã mount, hoặc trực tiếp orchestrator) với body claim `shop_id=X` nhưng JWT shop=Y → dùng shop từ JWT; missing JWT → 401.
24. `CreditLedger` model + Alembic 0006.
25. `agent/metering.py` debit/check logic + per-shop rate-limit.
26. `api/middleware.py` wrap chat endpoint.
27. STOP+WAIT (per-step confirm — RISK high, billing surface).

### Phase 6 — Eval harness (golden fixtures + multi-dim + regression gate CI)
<!-- ADP:PHASE 6 -->
STATUS: TODO
GOAL: Golden set N case per intent family (Roadmap §2, 15 loại); harness chạy 5 assertion dim (structural + grounding + action-correctness + tone + safety); rule-based + LLM-as-Judge combined; regression pass-rate < PRE-009 threshold → CI block merge; Manual Override Rate baseline metric persisted.
APPROACH: `agent/eval/` module với harness + judge + 5 assertion; `tests/eval/golden/*.jsonl` fixtures theo intent family; `agent/eval/harness.py` orchestrate run + report; CI workflow `.github/workflows/eval.yml` chạy trên PR + block nếu pass-rate < threshold; Manual Override Rate hook trong `api/inbox.py` (seller sửa/bỏ → log override event).
ALLOWED_FILES: agent/eval/__init__.py, agent/eval/harness.py, agent/eval/judge.py, agent/eval/structural.py, agent/eval/grounding.py, agent/eval/action.py, agent/eval/tone.py, agent/eval/safety.py, agent/eval/override.py, tests/eval/golden/, tests/test_eval_harness.py, .github/workflows/eval.yml, api/inbox.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_eval_harness.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_eval_harness.py tests/test_orchestrator.py tests/test_policy_gate.py -x -q && .venv/bin/python -m agent.eval.harness --check-baseline
RETRY: 0/3
RISK: high (proposed, pending Wyatt sign — regression gate là chốt chặn quality, sai gate = silent AI regression)
BLOCKED_BY: PRE-003 (pilot conv fixtures cho golden set) + PRE-009 (N + threshold)
<!-- /ADP -->

28. `test_eval_harness.py` (RED): (a) harness load golden fixture; (b) 5 assertion dim mỗi cái return pass/fail + score; (c) regression gate return non-zero exit khi pass-rate < threshold.
29. `agent/eval/{structural,grounding,action,tone,safety}.py` — mỗi assertion module implement per Roadmap §8.1.
30. `agent/eval/judge.py` — LLM-as-Judge cho tone/quality dim (rule-based cover structural/grounding/action/safety).
31. `agent/eval/harness.py` — orchestrate run + report + CI-friendly exit code.
32. `agent/eval/override.py` + hook trong `api/inbox.py` — Manual Override Rate log khi seller sửa/reject draft.
33. Load golden fixtures `tests/eval/golden/{intent_family}.jsonl` từ PRE-003 pilot conv.
34. CI workflow `.github/workflows/eval.yml` run on PR + block merge nếu fail.
35. STOP+WAIT (per-step confirm — RISK high).

### Phase 7 — Model router (plan_tier → model_id abstraction)
<!-- ADP:PHASE 7 -->
STATUS: TODO
GOAL: `agent/model_router.py` map `plan_tier → model_id`; orchestrator gọi router thay hardcode; credit cost tính theo model tier internal; đổi model chỉ sửa router config, không touch orchestrator; eval harness Phase 6 pass sau khi swap model.
APPROACH: `agent/model_router.py` với config `{Free: haiku, Normal: sonnet, Pro: opus}` (placeholder — Wyatt chốt cụ thể model id ở PRE-008 phần plan-tier mapping); orchestrator refactor gọi router.get(plan_tier); internal cost table theo tier (không expose seller-facing); regression eval sau swap phải pass.
ALLOWED_FILES: agent/model_router.py, agent/orchestrator.py, agent/metering.py, tests/test_model_router.py, tests/conftest.py, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_model_router.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_model_router.py tests/test_orchestrator.py tests/test_eval_harness.py -x -q
RETRY: 0/3
RISK: medium (proposed, pending Wyatt sign — agent/orchestrator.py trong RISK_PATHS; abstraction refactor không đổi behavior cuối)
BLOCKED_BY: Phase 6 (eval harness) + PRE-008 (plan tier mapping)
<!-- /ADP -->

36. `test_model_router.py` (RED): (a) `router.get("Free")` trả `haiku`; (b) `router.get("Pro")` trả `opus`; (c) unknown tier fallback default + log warning.
37. `agent/model_router.py` implement với config-driven map.
38. Refactor `agent/orchestrator.py` gọi router thay hardcode model id.
39. Extend `agent/metering.py` cost table per tier (internal).
40. Chạy Phase 6 eval harness — verify pass-rate không hạ sau swap.
41. STOP+WAIT.

### Phase 8 — Intent classifier + confidence-gated escalation
<!-- ADP:PHASE 8 -->
STATUS: TODO
GOAL: `agent/intent_classifier.py` route 15 loại intent (Roadmap §2); `agent/escalation.py` implement 4 trigger (query ngoài catalog + tranh chấp nhóm 12 + tone giận nhóm 13 + đa nghĩa cao); low-conf escalation → không draft, `pending_reply` status=`ESCALATED`, seller UI hiện "cần bạn tự trả lời" + context summary; spam nhóm 15 → suppress không tốn credit.
APPROACH: LLM classify + rule-based fallback cho intent; escalation module trigger check trước draft; `policy_gate.py` extend include escalation branch (không chỉ auto_send vs park mà thêm ESCALATED); `api/inbox.py` render UI hint; `agent/metering.py` skip debit khi intent=spam.
ALLOWED_FILES: agent/intent_classifier.py, agent/escalation.py, agent/policy_gate.py, agent/orchestrator.py, api/inbox.py, agent/metering.py, tests/test_intent_classifier.py, tests/test_escalation.py, tests/eval/golden/, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_intent_classifier.py tests/test_escalation.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_intent_classifier.py tests/test_escalation.py tests/test_policy_gate.py tests/test_orchestrator.py tests/test_eval_harness.py -x -q
RETRY: 0/3
RISK: high (proposed, pending Wyatt sign — agent/policy_gate.py + agent/orchestrator.py trong RISK_PATHS; failure mode "AI overconfident sai" chết người, escalation là mitigation #1)
BLOCKED_BY: Phase 6 (eval harness — cần để verify classifier accuracy trên golden set)
<!-- /ADP -->

42. `test_intent_classifier.py` (RED): fixture 15 loại → classify đúng ≥ threshold; multi-intent decomposition (nhóm "còn M ko, ship HN nhiêu, bao lâu?" → 3 intent parallel).
43. `test_escalation.py` (RED): (a) query ngoài Wiki+catalog → ESCALATED; (b) intent=nhóm 12 (refund) → ESCALATED kể cả conf cao; (c) tone giận nhóm 13 → ESCALATED; (d) đa nghĩa cao (>1 intent với similar conf) → ESCALATED; (e) intent=spam nhóm 15 → suppress, không debit credit.
44. `agent/intent_classifier.py` implement LLM + rule fallback.
45. `agent/escalation.py` 4 trigger.
46. Extend `agent/policy_gate.py` include ESCALATED branch (auto_send / park / ESCALATED).
47. Wire trong `agent/orchestrator.py` — gọi classifier trước draft, gọi escalation trước policy_gate.
48. `api/inbox.py` render UI hint "cần bạn tự trả lời" + context summary khi status=ESCALATED.
49. Extend `agent/metering.py` skip debit khi intent=spam.
50. Add golden fixture cho escalation cases (nhóm 12, 13, spam).
51. STOP+WAIT (per-step confirm — RISK high).

### Phase 9 — LLM observability + latency instrumentation
<!-- ADP:PHASE 9 -->
STATUS: TODO
GOAL: OTel span quanh `orchestrator.step` với attributes: `token_in/out`, `cost`, `model_id`, `tool_calls[]` (+ success/fail), `rag_hit`, `fallback_triggered`, `latency_ms`, `override`; trace correlation (conversation ID xuyên suốt LLM call + tool call + external API); cost attribution per shop/plan; latency p95 gate <5s trên 100+ msg fixture.
APPROACH: `agent/observability.py` OTel init + span helper; instrument `agent/orchestrator.py` + `bridge/ohana_client.py` + `bridge/zalo_sender.py` với span; conversation ID inject vào trace context; p95 gate qua test fixture 100+ msg.
ALLOWED_FILES: agent/observability.py, agent/orchestrator.py, bridge/ohana_client.py, bridge/zalo_sender.py, agent/llm_client.py, tests/test_observability.py, tests/test_latency_p95.py, tests/conftest.py, pyproject.toml, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_observability.py tests/test_latency_p95.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_observability.py tests/test_latency_p95.py tests/test_orchestrator.py -x -q
RETRY: 0/3
RISK: low (proposed, pending Wyatt sign — instrumentation additive, không đổi behavior; nhưng chạm agent/orchestrator.py trong RISK_PATHS → floor rule đề xuất bump lên medium, để Wyatt quyết)
<!-- /ADP -->

52. `test_observability.py` (RED): (a) span emit có 9 attribute; (b) conversation ID chạy xuyên suốt 3 layer (LLM call → tool call → external API); (c) cost attribution include shop_id.
53. `test_latency_p95.py` (RED): fixture 100 msg → p95 < 5000ms.
54. `agent/observability.py` OTel init + span helper.
55. Instrument `agent/orchestrator.py` + `bridge/ohana_client.py` + `bridge/zalo_sender.py` + `agent/llm_client.py`.
56. Add OTel deps vào `pyproject.toml`.
57. STOP+WAIT.

### Phase 10 — Zalo 48h reactive window scheduler + seller notification
<!-- ADP:PHASE 10 -->
STATUS: BLOCKED
GOAL: Scheduler track window 48h reactive per conversation; cảnh báo seller khi còn <T giờ trước hết window (T configurable, mặc định 6h); hết window mà chưa reply → notification + mark conversation expired-window.
APPROACH: `agent/scheduler.py` cron task (APScheduler hoặc similar) chạy mỗi 30min; query conversations với last_inbound_at + 48h - T còn active; emit notification event; `pending_reply` status=`WINDOW_EXPIRED` nếu quá hạn.
ALLOWED_FILES: agent/scheduler.py, db/models.py, api/inbox.py, tests/test_reactive_window.py, tests/conftest.py, pyproject.toml, docs/reviews/, docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE: .venv/bin/python -m pytest tests/test_reactive_window.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_reactive_window.py tests/test_zalo_sender.py -x -q
RETRY: 0/3
RISK: medium (proposed, pending Wyatt sign — chạm db/migrations trong RISK_PATHS; scheduler behavior time-sensitive)
BLOCKED_BY: Phase 2 done (RealZaloSender + webhook active) + PRE-004 (rate-limit + 48h window spec confirm)
<!-- /ADP -->

58. `test_reactive_window.py` (RED): (a) conversation với last_inbound_at 42h trước → emit warning; (b) 48h trước → status=WINDOW_EXPIRED; (c) inbound message reset timer.
59. ~~Add `last_inbound_at` column cho conversations + Alembic 0006.~~ ✅ **KHÔNG CÒN CẦN** — spec 06 F0 đã tạo bảng `conversations` KÈM `last_inbound_at` + `window_status`. Bước này chỉ còn đọc/ghi 2 cột đó.
60. `agent/scheduler.py` cron task 30min interval + logic query + notification.
61. `api/inbox.py` UI hint window countdown.
62. STOP+WAIT.

---

## §8 — DB Changes

> ⚠️ **AMENDED 2026-07-18 (sau spec 06 Foundation).** Ba sửa BẮT BUỘC, nếu không migration sẽ **fail khi apply**:
> 1. **Đánh số lại +1** — `0003` đã bị `0003_foundation_entities` (spec 06 F0) chiếm. Phase 1→**0004**, Phase 2→**0005**, Phase 5→**0006**.
> 2. **`UUID` → `TEXT`** — `shop_id` on-disk là `Text` ở mọi bảng (PRE-F01 Wyatt ký TEXT, KHÔNG migrate sang UUID). **FK kiểu UUID không tham chiếu được cột TEXT** → Postgres từ chối.
> 3. **Phase 10 KHÔNG còn migration** — spec 06 F0 đã tạo `conversations` kèm `last_inbound_at` + `window_status`. Bản cũ định `ALTER conversations` trên một bảng chưa từng CREATE.
>
> Mọi FK sang `customers`/`conversations` nên dùng **composite `(shop_id, <id>)`** như spec 06 F0 — FK đơn không chặn được row shop A trỏ row shop B.

- **Alembic 0004 (Phase 1):** `shops` table (`id TEXT, name TEXT, zalo_oa_id TEXT UNIQUE, plan_tier TEXT, is_active BOOL, created_at TIMESTAMPTZ`).
- **Alembic 0005 (Phase 2):** `webhook_event_log` table (`event_id TEXT PRIMARY KEY, shop_id TEXT FK, payload JSONB, signature TEXT, received_at TIMESTAMPTZ, processed_at TIMESTAMPTZ, status TEXT`).
- **Alembic 0006 (Phase 5):** `credit_ledger` table (`id TEXT, shop_id TEXT FK, delta INT, reason TEXT, conversation_id TEXT nullable, balance_after INT, created_at TIMESTAMPTZ`). Index `(shop_id, created_at DESC)`. `conversation_id` nên FK composite `(shop_id, conversation_id) → conversations(shop_id, id)`.
- ~~**Alembic 0006 (Phase 10):** ALTER `conversations` …~~ ✅ **HỦY** — spec 06 F0 (`0003_foundation_entities`) đã tạo `conversations` kèm `last_inbound_at TIMESTAMPTZ` + `window_status TEXT DEFAULT 'active'`. Phase 10 chỉ còn dùng 2 cột đó, không tạo migration mới.
- NEVER edit migration đã apply — thêm revision mới (R6 db pair).
- Mọi bảng mới đều có `shop_id` FK + index (R1.22 analog — tenant scope SQL-level).

---

## §9 — i18n Keys

- Escalation UI hint "cần bạn tự trả lời" + context summary label (Phase 8) — VI-first, port cơ chế i18n.
- Reactive window warning "còn X giờ để trả lời khách" (Phase 10) — VI-first.
- Credit balance warning "hết credit, nâng cấp gói" (Phase 5) — VI-first.
- Intent labels (Roadmap §2 15 loại) = **enum code**, không localized text — FE localize per shop language preference.
- KHÔNG hardcode string trong view — dùng cơ chế i18n như spec 01 §9.

---

## §10 — Post-checks

```
py_compile mọi file đổi
ruff check . && ruff format --check .
mypy app agent bridge tools
pytest -q (toàn bộ, không skip)
guardrail headless: python .claude/hooks/guardrail.py <changed files>
Reviewer subagent: chạy S-checklist adapt (S1 user_id+shop_id from JWT; S10 namespace isolation; S-new escalation trigger coverage)

Eval harness regression run:
  .venv/bin/python -m agent.eval.harness --full --threshold-check
  Expected: pass-rate >= PRE-009 threshold per dim

Manual Override Rate baseline setup:
  Deploy tới pilot shop → chạy ≥ 5 conv thật → verify override events log
  Expected: baseline Manual Override Rate per intent family recorded (Roadmap §8.1)

Trace correlation smoke test:
  Trigger 1 conv qua webhook → verify OTel trace có 1 conversation_id xuyên suốt:
    LLM call span + tool call span + external API span
  Expected: 1 trace, ≥3 span linked

Credit metering bypass test (adversarial):
  1. Gọi surface draft THẬT (biên orchestrator / webhook đã mount — KHÔNG có `/api/chat/draft`) với body {"shop_id": "X"} nhưng JWT shop=Y → debit trên Y (JWT wins)
  2. POST không JWT → 401
  3. POST khi balance=0 → 402
  Expected: 3/3 pass, không lách được

Manual E2E (post PRE unblock):
  Zalo real webhook → intent classify → escalation check → draft (nếu không escalate)
    → policy_gate → park pending_reply → seller approve → RealZaloSender send
  Expected: E2E 1 luồng qua Zalo staging OA thật
```

---

## §11 — Deliverables

- Repo `ohana-ai` @ main, 10 phase DONE, CI green (eval gate + pytest + ruff + mypy).
- Pilot 3–5 shop thật onboarded, chạy Zalo real E2E không lỗi.
- Eval harness pass rate ≥ PRE-009 threshold; Manual Override Rate baseline recorded.
- Latency p95 <5s trên 100+ msg fixture.
- Credit metering + rate-limit hoạt động, bypass test pass.
- Intent classifier + escalation cover 15 loại (Roadmap §2), nhóm 12-13 luôn escalate.
- OTel trace xuyên suốt 3 layer (LLM + tool + external API), cost attribution per shop.
- Hosting region ADR ACCEPTED (PRE-007), data-flow qua LLM provider quyết định.
- Commit pattern: `adp/03-GD0Backfill phase-N: <concern>`.

---

## §12 — Constraints (STOP conditions + anti-patterns)

- **STOP+WAIT** sau mỗi phase; per-step confirm cho Phase 1, 2, 5, 6, 8 (RISK: high proposed).
- **PRE-007 (hosting region ADR) BẮT BUỘC ACCEPTED trước Phase 1 execute** — data residency là kiến trúc constraint, không được vá sau.
- **ALLOWED_FILES là hard-bound** — KHÔNG touch file ngoài ALLOWED_FILES kể cả nếu "convenient" (scope-drift = R1.10 violation).
- **Additive/verify-first** — grep trước khi sửa module đã ship (spec 01 surface).
- **Auto-send KHÔNG bao giờ bỏ qua policy_gate** — Phase 8 extend policy_gate với ESCALATED branch, KHÔNG bypass.
- **AI KHÔNG tự quyết payment-confirm/discount/refund** (Roadmap §1.3 Guardrails) — Phase 8 escalation trigger phải cover intent 10 (payment), 12 (refund/hoàn), discount request.
- **`shop_id` / `user_id` / `role` CHỈ từ verified JWT** — không từ request body/webhook payload (R1.1 mở rộng spec 01).
- **Namespace/vector query luôn include `shop_id` SQL-level** — Phase 3 real corpus + Phase 5 credit_ledger + Phase 9 trace attribute đều phải scope-check (R1.22 analog).
- **Mock chỉ để unblock phase-gate** — acceptance-DONE cần real endpoint + real shop + real traffic (§11).
- **Không được self-certify DONE** — spine (adp-checkpoint.sh) quyết. STATUS: DONE thiếu EVIDENCE = chưa done.
- **Không được tự hạ RISK tier** — Wyatt sign; floor rule enforce (ALLOWED_FILES ∩ RISK_PATHS ⇒ ≥ medium).
- **KHÔNG token-based credit metering** (Roadmap §3.2) — per-lượt/outcome để tránh billing biến thiên gây lo âu seller.
- **KHÔNG dynamic complexity model routing** (Roadmap §8.2) — plan-tier trước, đo, rồi mới tính.
- **KHÔNG multi-provider LLM Spec 03** (Roadmap §1.2.12) — single-provider + heuristic fallback; multi-provider chỉ GĐ3+ nếu uptime data chứng minh.
- **KHÔNG framework migration / multi-agent / fine-tuning / guard model / generic reconcile sớm** (Roadmap §11 v3 rejected list).
- **Một patch = một concern** — bug phụ phát hiện → ghi KNOWN UNCOVERED, không fix (R1.10).
- **Verification Report (R8) bắt buộc mỗi phase** — không self-certify.

---

## §13 — Post-checks summary + tracking gate

**Post-check gate table (checkpoint per phase):**

| Check | Command | Phase applicable |
|---|---|---|
| pytest full | `.venv/bin/python -m pytest -q` | All |
| ruff | `.venv/bin/ruff check . && .venv/bin/ruff format --check .` | All |
| mypy | `.venv/bin/mypy app agent bridge tools` | All |
| eval regression | `.venv/bin/python -m agent.eval.harness --full --threshold-check` | Phase 6+, mọi phase touch agent/prompt/RAG |
| MOR baseline | manual pilot deploy + verify override log | Phase 6, 8 (baseline) |
| trace correlation | trigger 1 conv → verify OTel 3-span linked | Phase 9 |
| credit bypass | 3 adversarial POST → verify không lách | Phase 5 |
| Zalo E2E manual | webhook → draft → park → send qua Zalo staging | Phase 2, 10 (post PRE-004) |
| hosting ADR check | `test -f docs/adr/YYYY-MM-DD-hosting-region.md && grep -q "ACCEPTED" $_` | Phase 1 pre-check |

---

## §14 — Tracking

| Phase | Concern | RISK (proposed) | STATUS | BLOCKED_BY | EVIDENCE |
|---|---|---|---|---|---|
| PRE | 002/003/004/007/008/009 pre-flight | — | TODO | — | — |
| 1 | shops table + JWT extension real onboard | high | TODO | PRE-007 | — |
| 2 | Real ZaloSender + webhook sig + idempotency | high | BLOCKED | PRE-004 | — |
| 3 | Real Wiki corpus ingest (batch + delta) + admin | medium | BLOCKED | PRE-003 | — |
| 4 | F2 tools 2/3/4 (shipping/product/account) | medium | BLOCKED | PRE-002 | — |
| 5 | Credit metering + per-shop rate-limit | high | TODO | PRE-008 | — |
| 6 | Eval harness (golden + multi-dim + regression gate CI) | high | TODO | PRE-003 + PRE-009 | — |
| 7 | Model router (plan_tier → model_id) | medium | TODO | Phase 6 + PRE-008 | — |
| 8 | Intent classifier + confidence-gated escalation | high | TODO | Phase 6 | — |
| 9 | LLM observability + latency p95 gate | low→medium (Wyatt quyết) | TODO | — | — |
| 10 | Zalo 48h reactive window scheduler | medium | BLOCKED | Phase 2 + PRE-004 | — |

**Weekly Quality Review cadence (Roadmap §1.4):**
- Weekly: review failed golden case + production sample (post-pilot) + Manual Override Rate breakdown per intent family (Roadmap §2 15 loại).
- Dogfooding checkpoint: team dùng Ohana trả lời khách thật ≥1 lần/tuần.
- AI-specific PR checklist enforce mỗi patch touch `agent/*` · `orchestrator` · `policy_gate` · prompt: chạy eval? grounding assertion pass? touch RISK_PATH không? tool param validation?

**Parallel-lane execution (nếu PRE unblock lệch nhau):**
- **Lane A (không PRE-dependent):** Phase 1 (PRE-007) → Phase 5 (PRE-008) → Phase 9. Chạy trước.
- **Lane B (PRE-003):** Phase 3 → Phase 6 → Phase 7 → Phase 8. Chạy khi PRE-003 unblock.
- **Lane C (PRE-004):** Phase 2 → Phase 10. Chạy khi PRE-004 unblock.
- **Lane D (PRE-002):** Phase 4. Standalone.
- **Convergence:** Phase 6 gate cho Phase 7 + 8. Phase 2 gate cho Phase 10. Cả spec DONE khi 10/10 phase + all post-check.

> RISK tier = **proposed**, Wyatt finalize ở spec approval (DEC-019 floor rule). EVIDENCE do `adp-checkpoint.sh` ghi, không phải spec author. REVIEW do adp-review.sh stamp; RISK:high cần human review artifact bound cùng diff.

---

## Assumptions & Open (cần Wyatt/Tân chốt trước execute)

1. **Hosting region** (PRE-007) — VN/Singapore/US? Data-flow qua LLM provider region? PDPD 13/2023 compliance path? → ADR bắt buộc trước Phase 1.
2. **Credit pricing model** (PRE-008) — per-lượt cụ thể là gì? 1 credit/draft? /duyệt-gửi? /intent complexity? Plan tier mapping (Free X/Normal Y/Pro Z credit)?
3. **Golden set size + regression threshold** (PRE-009) — N per intent family? Pass-rate threshold cho CI gate?
4. **Model router config cụ thể** (PRE-008 phần liên quan) — Free=haiku/Normal=sonnet/Pro=opus có đúng ý Wyatt không?
5. **Ohana REST endpoint list** (PRE-002 inherited) — chờ Tân/nền tảng giao API doc.
6. **Real wiki corpus source + pilot conv anonymized** (PRE-003 inherited) — chờ Tân.
7. **Zalo OA creds + sig + rate-limit** (PRE-004 inherited) — chờ Tân.
8. **Reactive window warning threshold T** (Phase 10) — mặc định 6h trước hết 48h, Wyatt confirm?
9. **RISK tier final** cho 10 phase — proposal trong tracking table, Wyatt sign trước phase execute.
10. **Split spec decision** — spec 03 monolithic (10 phase) hay split thành 03a/b/c/d theo lane parallel? — Wyatt quyết ở review.
