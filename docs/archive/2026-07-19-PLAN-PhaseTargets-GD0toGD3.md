# PLAN — Phase Execution Targets (GĐ0 → GĐ3)

> **Loại tài liệu:** Planning / target companion cho [Roadmap v3](/Users/wyattngo/Desktop/Ohana/Roadmap.md) (canonical, Desktop). **KHÔNG phải ADP execution spec** — cố ý KHÔNG chứa phase block máy-đọc (`<!-- ADP … -->`) nên `adp-status.sh` không đếm (dashboard 15/25 giữ nguyên).
> **Mục đích:** với mỗi giai đoạn, liệt kê **spec/task cần thực hiện** + **target đo được cần đạt** + **blocker** + **RISK đề xuất** + **thứ tự dependency**.
> **Quy tắc thực thi:** mỗi spec bên dưới chỉ trở thành file `docs/tasks/NN-Task-*.md` (full ADP, có phase block) khi **unblock** — sinh qua `onfa-spec-generator`, Wyatt ký RISK, đúng như Spec 03 đã làm cho GĐ0. Tài liệu này là bản đồ, không phải lệnh execute.
> **Owner:** R: Tân · A: Wyatt (spec approval + RISK finalize). **Last updated:** 2026-07-18.
> **🔀 RE-SEQUENCED 2026-07-18 (Roadmap v4 §3.0):** ưu tiên 1 = **General Chat (Together LLM)** — ship trước, blocker duy nhất là Together key. Tính năng chính (RAG + F2 tools + policy-gate + Zalo) tiếp tục **sau khi có platform API từ Tân**. Provider chốt = **Together open-weight** (LLM + embedding e5-1024 thay OpenAI-1536). Residency: two-data-plane VN/US — ADR `docs/adr/2026-07-18-hosting-region.md`. Targets GĐ0 dưới đây vẫn đúng, chỉ **đổi thứ tự thực hiện**.

---

## 0. Numbering reconciliation (drift fix)

Roadmap v3 dùng nhãn `04a-d / 05a-f / 06a-f` — nhãn này **có trước** khi `04-InboxUI` và `05-ConfigEmbedder` được chèn vào on-disk. Số 04/05 **đã bị chiếm**. Bảng dưới ánh xạ nhãn roadmap → số spec thật kế tiếp trong `docs/tasks/` (next free = **06**). Nhãn a/b/c của roadmap giữ lại để truy vết.

| On-disk taken | GĐ | Spec |
|---|---|---|
| `01` | GĐ0 | GD0 backend (5/5 DONE) |
| `02` | GĐ0 | Bootstrap fork DrNickV4 (4/4 DONE) |
| `03` | GĐ0 | **GD0 Acceptance Backfill** (0/10 — 4 BLOCKED) |
| `04` | GĐ0.5 | Inbox UI (3/3 DONE) |
| `05` | GĐ0.5 | Config + Embedder F1 (3/3 DONE — F1 chờ live acceptance) |

| Spec mới (đề xuất) | Nhãn roadmap | GĐ | Concern |
|---|---|---|---|
| `06` | 04a | GĐ1 | Order state machine + transition audit log + webhook idempotency (generalize) |
| `07` | 04b | GĐ1 | Payment integration (1 provider) |
| `08` | 04c | GĐ1 | Shipping integration (1 carrier) |
| `09` | 04d | GĐ1 | COD reconciliation (1 carrier) |
| `10` | 05a | GĐ2 | Channel abstraction refactor (Zalo → base Protocol) |
| `11` | 05b | GĐ2 | FB Messenger channel |
| `12` | 05c | GĐ2 | Multi-carrier shipping (carrier #2 + fee policy config) |
| `13` | 05d | GĐ2 | COD reconciliation multi-carrier + generic engine + parity test |
| `14` | 05e | GĐ2 | Analytics Pro (script-first, dashboard sau) |
| `15` | 05f | GĐ2 | Semantic product discovery (VLM enrichment + facet + `product_search`) |
| `16` | 06a | GĐ3 | Recurring payment provider eval + integration |
| `17` | 06b | GĐ3 | Subscription billing (tier + credit chu kỳ + model tier gate) |
| `18` | 06c | GĐ3 | Reseller model (single-level flat) |
| `19` | 06d | GĐ3 | Rate-limit + monitoring + backup + log retention + worker isolation |
| `20` | 06e | GĐ3 | Multi-tenant isolation soak + JWT fuzz + query-planner audit + load test |
| `21` | 06f | GĐ3 | External security review (audit firm) |

**Priority order mọi GĐ (trừ GĐ4):** safety → user trust → stability → growth.

---

## 1. GĐ0 — MVP Wedge (Zalo-only, 1 shop thật)

**Mục tiêu:** người bán thấy AI trả lời hộ + duyệt-gửi trong 1 kênh (Zalo OA) trên **1 shop thật + traffic thật**. Bypass cold-start bằng single-player value.

**Technical gate (acceptance-DONE):** E2E shop thật + credit metering không bypass + **eval harness pass** + latency p95 <5s + escalation gate hoạt động.

**Spec cấu thành:**

| Spec | Concern | RISK | Trạng thái |
|---|---|---|---|
| 01 | Tenant-first foundation + policy-gate + mock Zalo/API | high/med | ✅ 5/5 DONE (mock) |
| 04 | Inbox UI (ChannelPicker · Inbox · ReviewCard · AdminWikiIngest) | medium | ✅ 3/3 DONE |
| 05 | `app/config.py` + `OpenAIEmbedder` thật (F1) | medium | ✅ 3/3 DONE · ⚠️ F1 chờ `pytest -m live` (ISSUE-016 OPEN) |
| **03** | **GĐ0 Acceptance Backfill (10 phase)** | high (mixed) | ⏳ **0/10** — chi tiết trong [`03-Task-GD0-AcceptanceBackfill.md`](03-Task-GD0-AcceptanceBackfill.md) |

**Target cần đạt (13 gap → close, Roadmap §3.2):**
- [ ] Zalo OA thật gửi/nhận E2E trên 1 shop thật (thay `MockZaloSender`, webhook `enabled=True` + signature-verify).
- [ ] `shops` table + JWT `shop_id` từ real onboard (không stub); cross-shop rejection test pass.
- [ ] **Eval harness pass** — golden set ≥ N case/intent family (15 loại §2), 5 dim (structural/grounding/action/tone/safety), regression gate CI block merge dưới threshold.
- [ ] Tool-call correctness + param validation trước execute (chặn tool hallucination).
- [ ] Intent classifier route 15 loại + suppress spam (không tốn credit).
- [ ] Confidence-gated escalation — nhóm 12/13 + ngoài catalog + tone giận + đa nghĩa → **không draft**, hiện "cần bạn tự trả lời" + tóm tắt.
- [ ] Credit metering per-lượt server-side, bypass test (body giả `shop_id`) không lách được; JWT wins.
- [ ] Per-shop rate-limit chặn cost blowout.
- [ ] `model_router` plan_tier → model_id (hết hardcode).
- [ ] Latency p95 <5s đo trên 100+ msg fixture (OTel span quanh `orchestrator.step`).
- [ ] Zalo 48h reactive window scheduler + cảnh báo seller trước hết window.
- [ ] Hosting region ADR ACCEPTED (data-flow qua LLM provider quyết định) — PRE-007.
- [ ] Pilot 3–5 shop thật chạy không lỗi.

**Blocker (chi tiết trong audit Spec 03):**
- External (Tân): PRE-002 (REST API) · PRE-003 (wiki corpus + ≥20 pilot conv) · PRE-004 (Zalo creds+sig).
- Nội bộ (Wyatt quyết, viết được ngay): PRE-007 (region ADR) · PRE-008 (credit pricing) · PRE-009 (golden N + threshold).
- Chạy được NGAY không cần ai: **Phase 9** (observability). Sau quyết định nội bộ: Phase 1 (PRE-007), Phase 5 (PRE-008).

**Cuối GĐ0:** submit Meta App Review (lead-time 4–8 tuần cho FB Messenger GĐ2).

**Duration:** 4–5 tuần sau khi PRE-002/003/004 unblock.

---

## 2. GĐ1 — Payment + Fulfillment cơ bản (1 provider + 1 carrier)

**Mục tiêu:** khép vòng chốt đơn → thu tiền → giao. **Prereq cứng: GĐ0 acceptance-DONE.**

**Technical gate:** payment webhook tự chuyển state + vận đơn thật + COD reconcile khớp + audit log mọi state transition.

**Spec cấu thành (tất cả net-new — on-disk không có `Order`/payment/shipping):**

| Spec | Concern | RISK | Depends |
|---|---|---|---|
| **06** | Order state machine (`draft→paid→shipped→delivered→refunded`) + explicit transition table + audit log mọi transition + generalize `webhook_event_log` (từ 03.2) cho payment/shipping | **high** | Spec 03 done |
| **07** | Payment integration 1 provider (VietQR **hoặc** MoMo) + `bridge/payment_client.py` (port pattern `ohana_client` verify=True) + `/webhook/payment/{provider}` | **high** | 06 |
| **08** | Shipping integration 1 carrier (GHTK **hoặc** GHN) + `bridge/shipping_client.py` + tạo vận đơn + tracking + `/webhook/shipping/{carrier}` | **high** | 06 |
| **09** | COD reconciliation 1 hãng: `net = COD − phí ship − phí COD` khớp raw carrier CSV | medium | 08 + ≥5 đơn COD thật |

**Target cần đạt (Roadmap §4.5):**
- [ ] Thanh toán online tự chuyển state không thao tác tay → **verify 1 giao dịch thật**.
- [ ] Tạo vận đơn thật + nhận ≥3 trạng thái webhook (created/picked/delivered) → **verify tracking ID thật**.
- [ ] `net = COD − phí ship − phí COD` khớp reconciliation report carrier → **verify 1 đơn COD thật** (không tự sinh test data — dùng raw carrier export).
- [ ] Mọi order transition có audit log entry → verify query log.
- [ ] Webhook idempotency: retry cùng event_id → dedup, no double-charge/double-ship.

**Rủi ro kỹ thuật giấu (Roadmap §4.3):**
- Idempotency webhook (dedup key `webhook_event_log` — infra đã land ở 03.2, GĐ1 generalize).
- Order state machine phải có **explicit transition table + audit log** (compliance + debug), không implicit.
- COD rounding drift → verify bằng CSV thật của carrier.

**Decision cần chốt trước execute:**
- Payment provider: VietQR hay MoMo? (VietQR không auto-charge → ảnh hưởng GĐ3 recurring).
- Carrier: GHTK hay GHN? (chốt theo shop pilot).

**Land-early note:** `channels/base.py Protocol` (abstraction kênh) nên land sớm (GĐ0/03 hoặc đầu GĐ1) — nếu hardcode Zalo trong `api/webhook.py`, refactor GĐ2 tốn 3–5× (Roadmap §5.2.1). Cùng lý do với webhook abstraction `/webhook/payment` + `/webhook/shipping`.

**Duration:** 4–6 tuần (không tính provider/carrier onboarding lead-time).

---

## 3. GĐ2 — Đa kênh + Đối soát COD + Analytics + Product Discovery

**Mục tiêu:** mở rộng surface + đối soát hoàn chỉnh + đo lợi nhuận + tư vấn khám phá sản phẩm.

**Technical gate:** 2 kênh qua abstraction (thêm kênh không sửa core) + reconcile đa hãng 100% + product RAG grounded.

**Spec cấu thành:**

| Spec | Concern | RISK | Depends |
|---|---|---|---|
| **10** | Channel abstraction refactor: Zalo migrate → `channels/base.py Protocol`, shape `channels/{zalo,messenger}/{inbound,outbound}.py` | **high** (touch core webhook) | GĐ1 done |
| **11** | FB Messenger channel implement | medium | 10 + **Meta App Review** (submit cuối GĐ0) |
| **12** | Multi-carrier shipping (add carrier #2 + fee policy config) | medium | 08 |
| **13** | COD reconciliation multi-carrier + **generic engine** + script parity test | **high** | 09 + 12 |
| **14** | Analytics Pro (script trước, dashboard sau) | medium | 13 |
| **15** | Semantic product discovery (VLM enrichment + facet taxonomy + `tools/product_search.py`) | **high** (overclaim → consumer trust) | retriever+channel+eval vững (song song được) |

**Target cần đạt (Roadmap §5.4):**
- [ ] 2 kênh song song qua 1 abstraction — **verify bằng chính việc port kênh 2 mà KHÔNG sửa core**.
- [ ] Đối soát COD đa hãng khớp **100%** trên raw carrier export CSV.
- [ ] Analytics khớp nguồn — reconciliation script pass ≥30 ngày data thật (script = source of truth, không tin dashboard nếu ≠ raw export).
- [ ] Product discovery: query NL → top-k grounded (facet đúng, không overclaim) → **eval grounding pass + human review enrichment sample**.

**Điểm quyết định kỹ thuật (Roadmap §5.2):**
- Channel abstraction land sớm (xem GĐ1 land-early note) — nếu không, refactor cost 3–5×.
- **Meta App Review = external dep** (~4–8 tuần). **Submit cuối GĐ0**. Kế hoạch B nếu reject: mở rộng Zalo-only.
- Reconciliation **KHÔNG generic sớm** — làm 1 hãng (GĐ1) thấy quirk → GĐ2 mới extract generic engine (chưa thấy 2 hãng thì không biết abstraction đúng).
- Product discovery = **VLM enrich-at-ingest (approach A), KHÔNG cross-modal CLIP** (§8.5). Taxonomy là phần khó nhất: hybrid facet kiểm soát (hard-filter) + blob mô tả (semantic recall). Enrichment hallucination = độc (schema-constrained + vocab kiểm soát + human sample + cấm overclaim "tôn dáng").

**Duration:** 6–8 tuần (Meta review có thể là critical path; 15 cộng thêm nếu chạy song song).

---

## 4. GĐ3 — Billing + Reseller + Hardening

**Mục tiêu:** production-ready SaaS: thu tiền tự động, phân phối qua reseller, chịu tải, security-reviewed.

**Technical gate:** recurring charge 1 chu kỳ + load target + security audit pass.

**Spec cấu thành:**

| Spec | Concern | RISK | Depends |
|---|---|---|---|
| **16** | Recurring payment provider eval + integration (VietQR không auto-charge → VNPay recurring? tokenized card?) | **high** | GĐ2 done |
| **17** | Subscription billing (tier Free/Normal/Pro + credit chu kỳ + model tier gate + up/downgrade) | **high** | 16 + `model_router` (03.7) |
| **18** | Reseller model (tier + charge hook + license CRUD) — **single-level flat** (ràng buộc kỹ thuật, không nested) | **high** | 17 |
| **19** | Rate-limit (mở rộng per-shop từ 03.5) + monitoring + backup + log retention + worker isolation (scoped theo shop) | medium | — |
| **20** | Multi-tenant isolation soak-test + JWT fuzz + query-planner data-isolation audit + load test | medium | 19 |
| **21** | External security review (audit firm) — critical path | — | 20 |

**Target cần đạt (Roadmap §6.4):**
- [ ] Recurring charge chạy **≥1 chu kỳ thật** (charge + retry + failure notification).
- [ ] Cấp/thu hồi license + tier đúng — **verify ≥3 reseller thật**.
- [ ] Load test đạt **N concurrent** (đề xuất N = 3× shop pilot cuối GĐ2, vd 300 pilot → 1000 concurrent).
- [ ] Security review **PASS** — không HIGH severity finding open.
- [ ] Multi-tenant isolation: soak concurrent + JWT fuzz + background job scoped theo shop + query-planner audit pass.

**Decision cần chốt:**
- Recurring provider (VietQR không auto-charge → thay/thêm). Chốt trước Spec 16.
- Load test target N cụ thể (theo shop pilot cuối GĐ2).
- Audit firm (external, lead-time là critical path).

**Duration:** 9–14 tuần (audit firm có thể là critical path).

---

## 5. GĐ4 — Financial AI (NGOÀI SCOPE)

Không viết chi tiết. **3 cảnh báo kỹ thuật bắt buộc trước khi start (Roadmap §7):**
1. **Eval/safety framework riêng** — priority order hiện tại không đủ cho crypto/BĐS/CK/vàng; reactivate framework kiểu ONFA (LR/WP/TV/UR).
2. **Spec-generator branch riêng** — không tái dụng template GĐ0-3.
3. **Kiến trúc khác bản chất** — Ohana = advisor, **không hold funds**; regulatory constraint từng asset class ảnh hưởng data model + hosting + audit trail — không port thẳng ONFA fintech code.

---

## 6. Dependency graph (corrected numbering)

```
GĐ0  Spec 03 (backfill: real Zalo + metering + EVAL + tool-call + model_router + intent + escalation + obs)
       ├─ External: hosting region ADR (PRE-007) — trước ship
       └─ Meta App Review submit ngay cuối GĐ0 (chuẩn bị GĐ2)
     [Gate GĐ0: E2E shop thật + eval pass + metering + escalation + p95]
       │
GĐ1  06 (order state + audit log + idempotency)  →  07 (payment 1 provider)
                                                  →  08 (shipping 1 carrier)  →  09 (COD reconcile, sau ≥5 đơn thật)
     [Gate GĐ1: payment/shipping/COD verify thật + audit log]
       │
GĐ2  10 (channel abstraction)  →  11 (FB Messenger, chờ Meta)
     12 (multi-carrier)        →  13 (generic reconcile)  →  14 (analytics)
     15 (product discovery — song song được)
     [Gate GĐ2: 2 kênh + reconcile đa hãng 100% + product RAG grounded]
       │
GĐ3  16 (recurring payment)  →  17 (subscription billing + model gate)  →  18 (reseller)
     19 (rate-limit + monitoring + worker iso)  →  20 (soak + fuzz + load)  →  21 (security audit)
     [Gate GĐ3: recurring charge + load target + audit PASS]
```

**Critical path GĐ0→GĐ3 (không delay Meta/provider onboarding):** ~24–35 tuần (~6–8 tháng).

**Abstraction phải land sớm để tránh refactor tax 3–5× (Roadmap §1.1.5):** channel · webhook · order state · credit metering · model routing.

---

## 7. Decision gate — Wyatt/Tân chốt gì trước mỗi GĐ

| GĐ | Cần quyết trước execute | Ai | Loại |
|---|---|---|---|
| **0** | PRE-007 hosting region (VN/SG/US + data-flow LLM provider) | Wyatt | ADR (viết được ngay) |
| **0** | PRE-008 credit pricing per-lượt (1 credit/draft? /duyệt-gửi?) + plan tier mapping | Wyatt | Business rule 1 dòng |
| **0** | PRE-009 golden N/intent + regression pass-rate threshold | Wyatt/Tân | Ngưỡng (cần PRE-003 pilot conv) |
| **0** | PRE-002/003/004 (REST API · wiki corpus+pilot conv · Zalo creds) | Tân/nền tảng | External deliverable |
| **1** | Payment provider (VietQR / MoMo) + Carrier (GHTK / GHN) | Wyatt/pilot shop | Provider choice |
| **1** | Channel `base.py Protocol` land sớm? (tránh refactor 3–5×) | Wyatt | Architecture |
| **2** | Meta App Review submit (cuối GĐ0) + kế hoạch B nếu reject | Wyatt | External timing |
| **2** | Product facet taxonomy (cổ/dáng/dịp…) + vocab kiểm soát | Wyatt/Tân | Data design |
| **3** | Recurring payment provider (VietQR không auto-charge) | Wyatt | Provider choice |
| **3** | Load test target N + audit firm | Wyatt | External + target |

---

## 8. Cross-cutting acceptance (mọi GĐ)

- **Eval regression gate** — đổi prompt/model/RAG → chạy golden suite, không hạ pass-rate dưới threshold (§8.1). Từ GĐ0 trở đi.
- **Hard grounding** — fact (tồn kho/giá/phí/trạng thái) → tool, cấm LLM đoán (§1.2.9). Nhóm intent 1,2,5,11.
- **Guardrails §1.3** — AI KHÔNG tự quyết: payment-confirm (chỉ webhook GĐ1) · discount/mặc cả (rule bounded/human) · hoàn/đổi (luôn human) · auto-send (policy_gate cứng).
- **Multi-tenant `shop_id` SQL-level** mọi query/vector/ledger/trace (R1.22 analog). Reviewer check patch touch `retrieval/*` · `db/*` · `orchestrator`.
- **RISK floor** — `files ∩ RISK_PATHS ≠ ∅ ⇒ ≥ medium`; Wyatt ký, agent không tự hạ.
- **Mock chỉ unblock phase-gate** — acceptance-DONE cần real endpoint + real shop + real traffic.
- **AI-specific PR checklist** mỗi patch touch `agent/*`·`orchestrator`·`policy_gate`·prompt: chạy eval? grounding pass? touch RISK_PATH? tool param validation? (§1.4).

---

*Tài liệu planning. Execution vẫn qua `docs/tasks/NN-Task-*.md` (spec-generator + ADP checkpoint). Conflict với Roadmap v3 → Roadmap thắng.*
