# PLAN — Tech-Lead Audit + Spec/Phase/Task Decomposition (toàn Roadmap)

> **Loại:** Tech-lead analysis + Work-Breakdown. Companion của [Roadmap v3](/Users/wyattngo/Desktop/Ohana/Roadmap.md) (canonical) và [PLAN-PhaseTargets](PLAN-PhaseTargets-GD0toGD3.md) (targets/acceptance).
> **Phân vai tài liệu:** Roadmap = *cái gì + tại sao*. PhaseTargets = *đạt mức nào thì DONE*. **File này = *chia thế nào + roadmap sai/thiếu ở đâu*.**
> **KHÔNG chứa phase block máy-đọc** (HTML-comment ADP marker) → `adp-status.sh` không đếm.
> **Grounding:** mọi finding dưới đây verified on-disk 2026-07-18 (không tin lời khai roadmap). **Last updated:** 2026-07-18.

---

## PHẦN A — Tech-lead audit (11 finding, đã verify on-disk)

Xếp theo mức chặn. TL-1/2/5 là **structural**, phải xử trước khi execute bất kỳ code GĐ0 nào ngoài Phase 9.

### 🔴 TL-1 — Data model lõi thương mại KHÔNG tồn tại (BLOCKER)
**Verify:** `db/models.py` chỉ có `Message`, `Embedding`, `PendingReply`. **Không** có `Conversation`, `Order`/`OrderDraft`, `Customer`.
**Mâu thuẫn cứng:**
- Roadmap §0 nói GĐ0 làm "order draft"; intent #9 "chốt đơn → extraction → draft" gán GĐ0 — **nhưng không bảng nào chứa order**.
- Spec 03 migration `0005 credit_ledger` có FK `conversation_id` → **trỏ vào bảng không tồn tại**.
- Spec 03 migration `0006` = `ALTER conversations ADD COLUMN …` → **ALTER một bảng chưa từng CREATE** (0001/0002 không tạo `conversations`). Migration này sẽ **fail khi apply**.

**Hệ quả:** ≥2 phase Spec 03 (5, 10) đứng trên nền không có. `orchestrator.receive_and_draft` nhận `message` rời rạc, không có khái niệm thread/đơn.
**Fix (tech-lead):** chèn **Phase Foundation** dựng `Conversation` + `OrderDraft` (+ `Customer` identity) tenant-scoped **TRƯỚC** credit_ledger (0005) và window (0006). Đây là spine đang thiếu — roadmap giả định nó có sẵn.

### 🔴 TL-2 — "Land abstraction sớm" (§1.1.5) KHÔNG có trong phase Spec 03 nào (contradiction)
**Verify:** không có `channels/`; `api/webhook.py` hardcode Zalo (`from bridge.zalo_sender import ZaloSender`, route `/webhook/zalo/{oa_id}`).
**Mâu thuẫn:** §5.2.1 + §4.2 nói channel + webhook abstraction "**land ngay Spec 03**", nhưng Spec 03 (10 phase) **không có phase abstraction nào** — nó bị đẩy sang Spec 05a (GĐ2). Roadmap tự cảnh báo refactor tax 3-5× nếu đợi, rồi tự lên lịch đợi.
**Fix:** kéo `channels/base.py Protocol` + generic webhook router vào **Foundation GĐ0**, migrate Zalo lên đó ngay. GĐ2 khi ấy chỉ *thêm* Messenger, không *mổ* core.

### 🔴 TL-5 — PRE-007 residency có thể **vô hiệu hoá F1 embedder đã ship** (latent bomb)
**Verify:** F1 = `OpenAIEmbedder` + `text-embedding-3-small` (endpoint OpenAI US).
**Rủi ro:** nếu PDPD/VN residency cấm dữ liệu khách rời VN, thì embed message text qua OpenAI US = vi phạm → phải đổi sang embedding model region-local → **re-embed toàn corpus + re-verify F1** (ISSUE-016 làm lại từ đầu).
**Fix:** PRE-007 ADR là **gate-0 của GĐ0**, chốt data-flow *khách → LLM provider* TRƯỚC khi wire thêm embedder/LLM. Đây KHÔNG phải paperwork — nó có thể viết lại AI stack.

### 🟠 TL-3 — Spec 03 = monolith 10-phase RISK:high (change-control hazard)
1 phase = 1 session; RISK:high = per-step confirm; 1 spec = 1 lock file. 10 phase high trong 1 spec ≈ 1 tháng dưới 1 `.sprint-spec.lock` → drift-risk cao, khó song song. Roadmap §14-Q10 tự hỏi "split?".
**Fix:** tách theo lane roadmap tự nhận (§14 parallel-lane) → **03a/b/c/d**, mỗi cái lock độc lập (chi tiết PHẦN C).

### 🟠 TL-4 — Eval chicken-and-egg (dependency vòng)
Spec 03 Phase 6 (eval) `BLOCKED_BY PRE-003` (pilot conv). Pilot conv cần **ship Zalo thật** (Phase 2 / PRE-004). Nhưng ship Zalo không có eval = đúng cái silent-regression roadmap sợ nhất.
**Fix (roadmap §8.1 đã gợi nhưng phase-graph mâu thuẫn):** tách eval —
- **eval-SEED**: harness + golden **tay** cho hard case (nhóm 12/13 + đa-intent + không dấu). KHÔNG PRE. Land trước, gate classifier.
- **eval-GROW**: nuôi golden từ pilot conv thật. = backfill PRE-003.

### 🟠 TL-6 — Credit metering không có endpoint để "wrap middleware"
Draft chạy trong orchestrator, kích bởi webhook (chưa mount). "Middleware wrap chat endpoint" (Spec 03.5 APPROACH) **không có endpoint nào để wrap**. Metering phải hook **biên orchestrator draft**, không phải HTTP middleware. (Carry từ audit Spec 03.)

### 🟠 TL-11 — Rate-limit "in-memory fallback" vỡ khi scale (Redis chưa wire)
CLAUDE.md: "Redis chưa wire". Spec 03.5 "Redis-backed nếu có, in-memory fallback". In-memory rate-limit = per-process → sai ngay khi >1 uvicorn worker (chính là điều kiện load test §6.4 + p95 100-msg). Metering counter cũng vậy.
**Fix:** Redis (hoặc shared store) là **infra prerequisite của metering/rate-limit thật**, không phải fallback tuỳ chọn. Đưa vào decision gate GĐ0.

### 🟡 TL-7 — GĐ1 payment provider khoá cứng vào GĐ3 recurring
§6.2.1: VietQR không auto-charge → GĐ3 recurring cần provider khác. Chọn VietQR ở GĐ1 = cam kết integrate payment **lần 2** ở GĐ3. Chọn có chủ đích, đừng để lộ ra ở GĐ3.

### 🟡 TL-8 — Meta App Review cần vật liệu sản xuất *trong* GĐ0
Meta review (gate GĐ2, 4-8 tuần) cần app chạy + privacy policy + demo, và chỉ submit được sau GĐ0-done. → coi **bộ hồ sơ Meta là deliverable GĐ0** (task song song), submit ngày-1 sau GĐ0-done để review chồng lên GĐ1.

### 🟡 TL-9 — Không có nền test/CI/fixtures (nợ ngầm, phình theo mỗi bảng mới)
ISSUE-014 (không conftest.py) đang OPEN. Mỗi bảng mới (shops/conversation/order/credit_ledger) cần DB fixture. Spec 03.6 giả định `.github/workflows/eval.yml` + pytest gate nhưng **chưa có CI setup nào**.
**Fix:** 1 phase "test/CI foundation" (conftest + fixture factory pg/pgvector + CI skeleton) sớm trong GĐ0, trước các phase nặng bảng.

### 🟡 TL-10 — Reseller entity (GĐ3) chưa mô hình hoá, đè lên identity GĐ0
§6.2.3 đặt reseller trên `users.reseller_tier`, nhưng Ohana shop-centric (`shop_id` khắp nơi). Quan hệ reseller↔shop↔user chưa định nghĩa. Defer GĐ3 nhưng **flag khi thiết kế identity GĐ0 (shops+JWT)** để không khoá chết đường mở reseller.

---

## PHẦN B — Đề xuất RE-PARTITION (khác roadmap ở đâu + tại sao)

| Roadmap gốc | Tech-lead sửa | Lý do |
|---|---|---|
| Spec 03 = 1 monolith 10-phase | Tách **03a/b/c/d** theo lane | TL-3 (lock độc lập, song song) |
| Không có data-model foundation | **+ Phase Foundation** (Conversation/OrderDraft/Customer) đầu 03a | TL-1 (migration 0005/0006 đang treo) |
| Channel abstraction ở Spec 05a (GĐ2) | Kéo `channels/base.py` vào **03a Foundation** | TL-2 (tránh refactor 3-5×) |
| Eval = 1 phase (03.6), block PRE-003 | Tách **eval-SEED** (no PRE) / **eval-GROW** (PRE-003) | TL-4 (phá vòng) |
| Không có CI/fixtures phase | **+ Phase test/CI foundation** trong 03a | TL-9 |
| PRE-007 = pre-flight chung | Nâng thành **gate-0**, trước mọi embedder/LLM wiring | TL-5 (đe doạ F1 đã ship) |
| Metering = HTTP middleware | Hook **orchestrator boundary** | TL-6 |
| Rate-limit in-memory fallback | Redis = **infra prereq**, không optional | TL-11 |

**Numbering** (reconcile drift `04a-d/05a-f/06a-f` roadmap vs on-disk — chi tiết trong [PLAN-PhaseTargets §0](PLAN-PhaseTargets-GD0toGD3.md)):
GĐ0 = Spec 03 (tách 03a-d) · GĐ1 = 06-09 · GĐ2 = 10-15 · GĐ3 = 16-21.

---

## PHẦN C — Work-Breakdown: Spec → Phase → Task

> Granularity theo horizon: **GĐ0 = full Spec/Phase/Task** (imminent + đang restructure). **GĐ1 = Spec/Phase + task sketch**. **GĐ2-3 = Spec/Phase coarse** (chưa fabricate task cho việc còn nhiều ẩn số — sinh khi unblock).

### GĐ0 — Spec 03 tách 4 sub-spec

#### ▸ Spec 03a — Foundation (RISK: high) · **PRE: none (chạy được ngay, trừ Redis cho metering)**
*Đây là spec chặn — mọi thứ khác đứng trên nó. TL-1/2/9.*

| Phase | Task | Gate (test RED trước) |
|---|---|---|
| **F0 · Data model lõi** | `Conversation`, `OrderDraft`, `Customer` (shop_id FK NOT NULL, tenant-scoped) · Alembic 0003 · repos · mở rộng `test_tenant_isolation` sang bảng mới | cross-shop rejection trên `Conversation`/`OrderDraft` pass |
| **F1 · Channel/webhook abstraction** | `channels/base.py Protocol` (inbound/outbound) · migrate Zalo adapter lên đó · generic `/webhook/{channel}/{oa_id}` router · giữ interface `ZaloSender` | contract test channel-agnostic; Zalo path vẫn xanh |
| **F2 · Test/CI foundation** | `tests/conftest.py` + DB fixture factory (ephemeral pg+pgvector) · CI skeleton `.github/workflows/{ci,eval}.yml` (pytest+ruff+mypy) · baseline xanh | CI chạy green trên HEAD; ISSUE-014 đóng |

#### ▸ Spec 03b — Shops + Metering + Observability (RISK: high) · **PRE-007 (gate-0) + PRE-008 + Redis**
*Lane "không chờ Tân". Đứng trên 03a-F0.*

| Phase | Task | Gate |
|---|---|---|
| **B1 · shops + JWT real onboard** | `Shop` model · `POST /api/admin/shops` · `auth/identity.py` load shop_id từ DB (bỏ stub) · adversarial cross-shop | `test_shops_onboard` cross-shop reject |
| **B2 · Credit metering + rate-limit** | `CreditLedger` (FK conversation_id — giờ *có* bảng) · `agent/metering.py` debit tại **biên orchestrator** (TL-6) · per-shop rate-limit Redis (TL-11) · bypass test (JWT wins) | `test_metering_bypass` 3/3, balance=0→402 |
| **B3 · Observability + p95** | `agent/observability.py` OTel span quanh `orchestrator.step` (9 attr) · trace correlation conversation_id · p95<5s / 100-msg fixture | `test_latency_p95` p95<5000ms |

#### ▸ Spec 03c — Real Zalo E2E (RISK: high) · **PRE-004**
*Đứng trên 03a-F1 (abstraction) + F0 (Conversation).*

| Phase | Task | Gate |
|---|---|---|
| **C1 · RealZaloSender + webhook sig + idempotency** | `RealZaloSender` (httpx+retry) qua channel abstraction · `WebhookEventLog` · signature verify + dedup event_id | `test_zalo_sender` + `test_webhook_idempotency` |
| **C2 · 48h reactive window scheduler** | `agent/scheduler.py` cron 30min · dùng `Conversation.last_inbound_at` (0006 giờ ALTER bảng *có thật*) · seller notify <T giờ | `test_reactive_window` warning+expired+reset |

#### ▸ Spec 03d — Data + AI-layer (RISK: high) · **PRE-002 + PRE-003 + PRE-009**
*Đứng trên 03a-F2 (eval CI) + 03b (model tier cho router).*

| Phase | Task | Gate |
|---|---|---|
| **D1 · Real wiki corpus ingest** | batch + delta (doc_hash dedup) · admin multipart upload | `test_wiki_batch_ingest` + `test_wiki_delta` |
| **D2 · F2 tools 2/3/4** | `shipping_info`/`product_info`/`account_lookup` · param validation schema trước execute | `test_f2_tools` MockTransport shape |
| **D3 · eval-SEED** (TL-4, **no PRE**) | harness + 5 dim + golden **tay** hard-case (12/13 + đa-intent + không dấu) + regression gate CI | `test_eval_harness` gate non-zero khi <threshold |
| **D4 · model_router** | `agent/model_router.py` plan_tier→model_id · orchestrator bỏ hardcode · cost per tier nội bộ | `test_model_router` + eval không hạ sau swap |
| **D5 · intent classifier + escalation** | classify 15 loại + multi-intent decompose · escalation 4 trigger · policy_gate thêm branch ESCALATED · suppress spam (skip debit) | `test_intent_classifier` + `test_escalation` |
| **D6 · eval-GROW** (backfill) | nuôi golden từ pilot conv thật + Manual Override Rate baseline | golden ≥ N/intent family, MOR logged |

**GĐ0 acceptance** (từ [PhaseTargets §1](PLAN-PhaseTargets-GD0toGD3.md)) + **Meta submission materials** (TL-8, task song song).

---

### GĐ1 — Spec 06-09 (Spec→Phase, task sketch)

| Spec | Phase | Depends-on foundation |
|---|---|---|
| **06 · Order state machine** (high) | P1 state table `draft→paid→shipped→delivered→refunded` (explicit transition + audit log mọi transition) · P2 generalize `webhook_event_log` cho payment/shipping | **Mở rộng `OrderDraft`→`Order` từ 03a-F0** (không dựng lại) · idempotency từ 03c-C1 |
| **07 · Payment 1 provider** (high) | P1 `bridge/payment_client.py` (port pattern ohana_client) · P2 `/webhook/payment/{provider}` (qua webhook abstraction 03a-F1) · P3 state transition paid | 06 · TL-7 chọn provider có tính GĐ3 |
| **08 · Shipping 1 carrier** (high) | P1 `bridge/shipping_client.py` · P2 vận đơn+tracking · P3 `/webhook/shipping/{carrier}` | 06 |
| **09 · COD reconciliation** (medium) | P1 script `net = COD − ship − COD-fee` vs raw carrier CSV · P2 parity test | 08 + ≥5 đơn COD thật |

### GĐ2 — Spec 10-15 (Spec→Phase coarse)

| Spec | Phase chính | Ghi chú tech-lead |
|---|---|---|
| **10 · Channel abstraction** (high) | *Nếu 03a-F1 đã land đúng → 10 co lại còn "harden base Protocol"* | TL-2: phần lớn đã kéo về GĐ0 |
| **11 · FB Messenger** (medium) | inbound/outbound adapter | chờ Meta review (submit cuối GĐ0, TL-8) |
| **12 · Multi-carrier** (medium) | add carrier #2 + fee policy config | thấy quirk hãng #1 (GĐ1) trước |
| **13 · Generic reconcile** (high) | extract engine từ 2 hãng + parity | KHÔNG generic sớm (§5.2.4) |
| **14 · Analytics Pro** (medium) | script trước → dashboard sau | script = source of truth |
| **15 · Product discovery** (high) | VLM enrich pipeline + facet taxonomy + `product_search` | taxonomy = phần khó nhất (§8.5); song song được |

### GĐ3 — Spec 16-21 (Spec→Phase coarse)

| Spec | Phase chính | Ghi chú |
|---|---|---|
| **16 · Recurring payment** (high) | provider eval + integrate | VietQR không auto-charge (TL-7) |
| **17 · Subscription billing** (high) | tier + credit chu kỳ + model gate + up/downgrade | dùng `model_router` 03d-D4 |
| **18 · Reseller** (high) | tier + charge hook + license CRUD single-level | entity chưa mô hình (TL-10) |
| **19 · Hardening infra** (medium) | rate-limit mở rộng + monitoring + backup + worker isolation | rate-limit đã có nền 03b-B2 |
| **20 · Isolation soak + load** (medium) | soak concurrent + JWT fuzz + query-planner audit + load N | N=3× pilot cuối GĐ2 |
| **21 · Security audit** (—) | external audit firm | critical path lead-time |

---

## PHẦN D — Critical path (đã sửa) + thứ tự khởi động

```
GATE-0  PRE-007 residency ADR  ──►  (có thể buộc đổi F1 embedder — làm TRƯỚC)
   │
03a Foundation (data model + channel abstraction + CI)   ← chạy được NGAY, không chờ Tân
   ├─► 03b Shops+Metering+Obs      (PRE-007✓ + PRE-008 + Redis)
   ├─► 03c Real Zalo E2E           (PRE-004 — chờ Tân)
   └─► 03d Data + AI-layer         (PRE-002/003/009 — chờ Tân; nhưng D3 eval-SEED chạy được ngay)
        └─ [GĐ0 acceptance] + Meta submit
             │
GĐ1  06 order-state ─► 07 payment / 08 shipping ─► 09 COD reconcile
             │
GĐ2  10→11 (Meta) · 12→13 · 14 · 15  |  GĐ3  16→17→18 · 19→20→21
```

**🔀 CẬP NHẬT 2026-07-18 (Roadmap v4 §3.0) — ưu tiên 1 chèn lên đầu:**
**★ General Chat (Together LLM)** — seller ↔ AI chat trong app. Blocker **duy nhất** = Together key (Wyatt cấp). KHÔNG Zalo / KHÔNG RAG / KHÔNG F2 tools / KHÔNG cần embedding ⇒ **F1 embedder swap không chặn**. Ship trước để có single-player value + dogfooding + de-risk tích hợp Together. Chi tiết scope IN/OUT: Roadmap §3.0. RISK: medium.
→ Tính năng chính (03c/03d) giữ nguyên nhưng **chờ Tân** như cũ.

**Khởi động được NGAY, không cần Tân, không cần quyết định lớn:**
1. **PRE-007 ADR** (gate-0) — tôi draft, Wyatt chốt region. Mở khoá + bảo vệ F1.
2. **03a Foundation** — data model + channel abstraction + CI. Không PRE. Đây là việc đúng-để-làm-tiếp: nó vá TL-1 (migration đang treo) và TL-2 (refactor tax).
3. **03d-D3 eval-SEED** — harness + golden tay. Không PRE. Phá vòng TL-4.

**Chờ Wyatt quyết:** PRE-008 pricing · Redis infra (TL-11) · payment/carrier provider (TL-7).
**Chờ Tân:** PRE-002/003/004.

---

## PHẦN E — Thay đổi so với tài liệu hiện có

- **KHÔNG sửa** `03-Task-GD0-AcceptanceBackfill.md` (frozen-ish, đã có audit). Đề xuất tách 03a-d ở đây là *proposal* — chỉ hiện thực khi Wyatt duyệt (sinh spec con qua `onfa-spec-generator`).
- **PhaseTargets** giữ nguyên vai trò targets; file này thêm lớp *audit + partition*.
- **2 nợ drift** (từ audit trước) vẫn treo chờ duyệt: `api/chat.py` ma trong header Spec 03; migration `0006` ALTER `conversations` không tồn tại (giờ nâng thành TL-1, phải fix bằng Foundation F0).

---

*Tài liệu tech-lead. Proposal, chưa frozen. Execution qua `docs/tasks/NN-Task-*.md` (spec-generator + ADP checkpoint). Conflict với Roadmap v3 → nêu ra để Wyatt phân xử, KHÔNG tự override.*
