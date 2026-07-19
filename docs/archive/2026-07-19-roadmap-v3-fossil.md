# Ohana AI — Product Tech Roadmap

> **Sub-project:** `ohana-ai/` (workspace `localhost/`). Router: [`../CLAUDE.md`](../CLAUDE.md).
> **Owner:** R: Tân (dev lead) · A: Wyatt (fractional CTO — spec approval + RISK tier).
> **Last updated:** 2026-07-17.
> **Status:** GĐ0 spec-DONE, chưa acceptance-DONE (backfill Spec 03 pending). Chưa unlock 100M.

---

## 0. Tranche map (contract)

| GĐ | Milestone | Ngân sách | Trạng thái |
|---|---|---|---|
| GĐ0 | MVP Wedge (Zalo-only, 1 shop, không payment) | mở 100M sau acceptance | Spec 01 = 5/5 phase DONE với **mock**. Chưa E2E shop thật, chưa credit metering, chưa cross-border data plan. |
| GĐ1 | Payment + Fulfillment cơ bản | 150M #1 | Chưa bắt đầu. Prerequisite: GĐ0 acceptance-DONE. |
| GĐ2 | Đa kênh + Đối soát COD + Analytics | 150M #2 | Chưa bắt đầu. **Meta App Review submit ngay cuối GĐ0** (chu kỳ 4-8 tuần). |
| GĐ3 | Hardening + Billing subscription + Reseller | 150M #3 | Chưa bắt đầu. Reseller model đã verify pháp lý (NĐ 40/2018). |
| GĐ4 | Financial AI (crypto/BĐS/CK/vàng) | Ngân sách riêng, ngoài 600M | Ngoài scope hiện tại. **Cảnh báo:** phải reactivate Survival Framework (LR/WP/TV/UR) như ONFA — priority order Ohana hiện tại KHÔNG đủ. |

**Priority order Ohana (mọi GĐ trừ GĐ4):** safety → user trust → stability → growth.

---

## 1. Nguyên tắc chung (áp dụng mọi GĐ)

1. **ADP v2.3 discipline.** Mỗi GĐ ≥ 1 spec `docs/tasks/NN-Task-*.md`. Phase gate-passed = test exit 0 + diff-binding + human sign (RISK:high). Không self-certify.
2. **Prerequisite hard-block trước ship.** Spec block STATUS: BLOCKED nếu PRE-* chưa RESOLVED. Không chạy song song "vá sau".
3. **RISK tier do Wyatt gán,** agent không tự hạ. Money-adjacent code → tối thiểu `medium`, thường `high`.
4. **Test parity với production shape.** Mock chỉ để unblock phase-gate; acceptance-DONE cần real endpoint + real shop + real traffic.
5. **Land abstraction sớm.** Refactor tax cao gấp 3-5× nếu đợi GĐ sau (channel, webhook, order state, credit metering).
6. **Legal/compliance parallel-track.** DPA + PDPD 13/2023 + Meta App Review không phải Claude làm, nhưng phải nằm trên critical path — Wyatt escalate với legal counsel.

---

## 2. GĐ0 — MVP Wedge → unlock 100M

**Mục tiêu:** người bán thấy AI trả lời hộ + duyệt-gửi trong 1 kênh (Zalo OA). Bypass cold-start bằng cách không cần mạng lưới.

### 2.1 Trạng thái shipped (Spec 01)

- ✅ Phase 2 (RISK:high) — Multi-tenancy foundation (`shop_id NOT NULL` mọi bảng, JWT `(user_id, shop_id, role)`, `PgvectorRetriever(shop_scope=)` SQL-level).
- ✅ Phase 3 (low) — Wiki RAG (`parsing/`, `tools/wiki.py`, `api/admin.py` ingest).
- ✅ Phase 4 (medium) — Ohana REST client (`bridge/ohana_client.py`, `tools/ohana_read.py order_status`) với MockTransport contract.
- ✅ Phase 5 (RISK:high) — `agent/policy_gate.py`, `agent/orchestrator.py`, `PendingReply` table, `bridge/zalo_sender.py MockZaloSender`, `api/{webhook,inbox}.py` scaffold.

### 2.2 Gap giữa spec-DONE và acceptance-100M

| Acceptance criteria | Trạng thái | Gap |
|---|---|---|
| Zalo OA thật gửi/nhận E2E (1 shop thật) | ❌ | `MockZaloSender`, webhook `enabled=False` — cần PRE-004 (creds + signature + rate-limit) → wire real sender + sig-verify middleware + `shops` table |
| Latency gợi ý p95 < 5s | ❓ chưa đo | Cần Wiki thật + Ohana API mock latency-injected + OTel span quanh `orchestrator.step` + p95 trên 100+ msg fixture |
| Credit metering server-side, không bypass được | ❌ **không có trong spec 01** | Bảng `credit_ledger` tenant-scope + middleware trừ credit theo tool-call kind → test bypass bằng call API trực tiếp với body giả |
| Không code path bypass duyệt | ✅ policy-gate + reviewer đã enforce | Cần soak-test ≥5 decision thật trước khi SHADOW → hard-block (per memory `ohana-adp-v2.3-governance`) |
| Pilot 3–5 shop thật chạy không lỗi | ❌ | Blocker = PRE-002/003/004 unblock |
| Cross-border data compliance (DPA + PDPD 13/2023) | ❌ **không có trong spec 01** | Legal/architect spec riêng — quyết định region hosting, DPA với Zalo, filing PDPD |
| Zalo 48h reactive window cảnh báo seller | ❌ | Flag §4 spec 01 nhưng chưa impl — cần scheduler cron |

### 2.3 Spec 03 (đề xuất) — GĐ0 Acceptance Backfill

**Tên:** `03-Task-GD0-AcceptanceBackfill.md` · **RISK: high** · **Type: SPRINT, 5-7 phase**

| Phase | Nội dung | RISK | Prerequisite |
|---|---|---|---|
| 3.1 | `shops` table + JWT extension include `shop_id` từ real onboard flow (không stub) | high | — |
| 3.2 | Real `ZaloSender` (wire Zalo Send API) + webhook signature verify + `webhook_event_log` idempotency | high | PRE-004 unblock |
| 3.3 | Real Wiki corpus ingest (batch + delta) + admin UI upload | medium | PRE-003 unblock |
| 3.4 | F2 tools thứ 2/3/4 (`shipping_info`, `product_info`, `account_lookup`) | medium | PRE-002 unblock |
| 3.5 | Credit metering (`credit_ledger` + middleware + bypass test) | high | — |
| 3.6 | Latency instrumentation (OTel + p95 gate) | low | — |
| 3.7 | Zalo 48h reactive window scheduler + seller notification | medium | 3.2 done |

**Legal parallel (không phải Claude):** DPA với Zalo + PDPD 13/2023 filing. Wyatt escalate.

**Duration ước lượng:** 2-3 tuần sau khi Tân giao PRE-002/003/004.

### 2.4 Blocker cần Tân giao trước khi execute

- PRE-002: Ohana platform REST API spec (order/shipping/product/account endpoints)
- PRE-003: Real wiki docs corpus location + format
- PRE-004: Zalo OA creds + webhook signature + rate-limit spec

---

## 3. GĐ1 — Payment + Fulfillment cơ bản → 150M #1

**Mục tiêu:** khép vòng chốt đơn → thu tiền → giao.

### 3.1 Scope

- Payment link thật (VietQR/MoMo) + webhook xác nhận → tự cập nhật trạng thái đơn.
- Tích hợp 1 hãng vận chuyển (GHTK **hoặc** GHN, chốt theo shop pilot): tạo vận đơn, tracking, webhook trạng thái.
- COD flow cơ bản (chưa cần đối soát đa hãng).

### 3.2 Ánh xạ code hiện có

- Pattern `bridge/ohana_client.py` (verify=True, REST client) tái sử dụng được → port sang `bridge/payment_client.py` + `bridge/shipping_client.py`. **Thắng lợi thiết kế Phase 4 spec 01** — ROI cao.
- `api/webhook.py` hiện chỉ handle Zalo inbound. Thêm route `/webhook/payment/{provider}` + `/webhook/shipping/{carrier}` — **abstraction phải land ngay Spec 03**, không đợi GĐ2.

### 3.3 Rủi ro giấu (cần address trước GĐ1 execute)

1. **Idempotency webhook** — payment/shipping webhook sẽ retry. Cần `webhook_event_log` với dedup key. Land ở Spec 03.2.
2. **Order state machine** (`draft → paid → shipped → delivered → refunded`) — bảng `Order` mới, RISK: high (money-adjacent).
3. **COD net = COD − phí ship − phí COD** — dễ lệch vài đồng nếu rounding rule không khớp carrier. Verify bằng reconciliation report CSV thật, không tự sinh test data.

### 3.4 Specs đề xuất (split để dễ review)

| Spec | Nội dung | RISK | Prerequisite |
|---|---|---|---|
| **04a** | Order state machine + webhook idempotency infra | high | Spec 03 done |
| **04b** | Payment integration (1 provider — VietQR **hoặc** MoMo, chốt theo shop pilot) | high | 04a |
| **04c** | Shipping integration (1 carrier) | high | 04a |
| **04d** | COD reconciliation (script đối soát 1 hãng) | medium | 04c + ≥5 đơn COD thật |

### 3.5 Acceptance (đo được, ADP verify)

- Thanh toán online tự chuyển trạng thái không thao tác tay → verify bằng 1 giao dịch thật.
- Tạo vận đơn thật + nhận ≥3 trạng thái webhook (created / picked / delivered) → verify bằng tracking ID thật.
- `net = COD − phí ship − phí COD` khớp reconciliation report của carrier → verify 1 đơn COD thật.

### 3.6 Duration ước lượng

- 4a: 1 tuần · 4b: 1-2 tuần (KYC provider có thể trễ) · 4c: 1-2 tuần (KYC carrier + sandbox → prod) · 4d: 1 tuần sau khi có traffic thật.
- **Tổng: 4-6 tuần**, không tính KYC.

---

## 4. GĐ2 — Đa kênh + Đối soát COD + Analytics → 150M #2

**Mục tiêu:** mở rộng surface + đối soát hoàn chỉnh + đo được lợi nhuận.

### 4.1 Scope

- Kênh 2 (FB Messenger) qua abstraction layer — thêm kênh không sửa core.
- Đa hãng vận chuyển + đối soát COD đầy đủ (net, phí 2 chiều, đơn hoàn).
- Analytics gói Pro: doanh thu, COD chờ / đã đối soát, lỗ do hoàn.

### 4.2 Điểm quyết định trước khi execute

1. **Channel abstraction layer** — nếu GĐ0/GĐ1 wire Zalo hardcoded trong `api/webhook.py`, GĐ2 phải refactor với cost 3-5×. **Land ngay Spec 03** (base còn sạch).
   - Shape đề xuất: `channels/{zalo,messenger}/{inbound,outbound}.py` + `channels/base.py Protocol`.
2. **FB Messenger** cần Meta App Review (~4-8 tuần).
   - **Action:** Wyatt/Tân submit App Review **cuối GĐ0**, không đợi GĐ2 mới nộp.
3. **Reconciliation script = source of truth.** Không tin dashboard nếu script không match raw carrier export. Land script trước dashboard.

### 4.3 Specs đề xuất

| Spec | Nội dung | RISK |
|---|---|---|
| **05a** | Channel abstraction refactor (Zalo migrate → base Protocol) | high (touch core webhook) |
| **05b** | FB Messenger channel implement | medium |
| **05c** | Multi-carrier shipping (add carrier #2 + fee policy config) | medium |
| **05d** | COD reconciliation multi-carrier + script parity test | high |
| **05e** | Analytics Pro (doanh thu / COD status / lỗ hoàn) — script trước, dashboard sau | medium |

### 4.4 Acceptance

- 2 kênh song song qua 1 abstraction — verify bằng chính việc port kênh 2 mà không sửa core.
- Đối soát COD đa hãng khớp 100% trên tập test (raw carrier export CSV).
- Số liệu analytics khớp nguồn — reconciliation script pass trên ≥30 ngày data thật.

### 4.5 Duration ước lượng

- 05a: 1 tuần · 05b: 2 tuần + Meta review wait · 05c-d: 2 tuần · 05e: 1-2 tuần.
- **Tổng: 6-8 tuần** (Meta review có thể là critical path).

---

## 5. GĐ3 — Hardening + Billing + Reseller → 150M #3

**Mục tiêu:** production-ready SaaS: thu tiền tự động, phân phối qua reseller, chịu tải, security-reviewed.

### 5.1 Scope

- **Billing subscription** — recurring payment Free/Normal/Pro, quản credit theo chu kỳ.
- **Reseller/licensing** wholesale chiết khấu bậc (40/45/50%) — **KHÔNG hoa hồng đa cấp** (NĐ 40/2018 đã verify).
- **Hardening** — rate-limit, monitoring, log, backup, security review (bên ngoài), load test, multi-tenant isolation soak-test.

### 5.2 Điểm cần quyết trước khi execute

1. **Recurring payment provider** — VietQR không tự auto-charge → cần thay/thêm (VNPay recurring? Stripe VN? Tokenized card?). Quyết định trước Spec 06.
2. **Multi-tenant isolation** — foundation từ Phase 2 spec 01 đã có (`shop_id` scope SQL-level), test cover 3 case. GĐ3 cần soak-test ≥1000 shop concurrent + JWT fuzz test.
3. **Reseller model rõ ràng flat single-level** — flag trong RULES để agent không tự sinh nested logic. FK `users.reseller_tier` → `reseller_tiers`, billing hook chia rev-share tại điểm charge.
4. **Security review** = external audit firm, không phải Claude. Nằm trên critical path GĐ3.
5. **Load test target chưa có số** — user chốt "N shop" nhưng chưa gán. **Đề xuất:** N = 3× số shop pilot cuối GĐ2 (ví dụ 300 pilot → load-test 1000 concurrent).

### 5.3 Specs đề xuất

| Spec | Nội dung | RISK |
|---|---|---|
| **06a** | Recurring payment provider evaluation + integration | high |
| **06b** | Subscription billing (Free/Normal/Pro tier, credit chu kỳ, upgrade/downgrade) | high |
| **06c** | Reseller model (tier + rev-share hook + license CRUD) | high |
| **06d** | Rate-limit + monitoring + backup + log retention | medium |
| **06e** | Multi-tenant isolation soak-test + JWT fuzz + load test | medium |
| **06f** | External security review (audit firm, không phải Claude implement) | — |

### 5.4 Acceptance

- Thu subscription tự động chạy ≥1 chu kỳ thật (charge + retry + failure notification).
- Cấp/thu hồi license + chiết khấu bậc đúng — verify bằng ≥3 reseller thật.
- Load test đạt N shop đồng thời (chốt số) + security review PASS (không HIGH severity finding open).

### 5.5 Duration ước lượng

- 06a: 2-3 tuần (KYC provider) · 06b: 2 tuần · 06c: 1-2 tuần · 06d: 1 tuần · 06e: 1-2 tuần · 06f: 2-4 tuần (external firm).
- **Tổng: 9-14 tuần** (audit firm có thể là critical path).

---

## 6. GĐ4 — Financial AI (ngoài 600M)

**Ngoài scope hiện tại.** Không viết chi tiết trong roadmap này.

**Cảnh báo bắt buộc trước khi start GĐ4:**

1. **Reactivate Survival Framework** (LR/WP/TV/UR) như ONFA — priority order Ohana hiện tại (safety→trust→stability→growth) KHÔNG đủ cho crypto/BĐS/chứng khoán/vàng.
2. **Spec-generator branch riêng** — không tái sử dụng template GĐ0-3.
3. **Legal/regulatory** — mỗi asset class có quy định riêng (SBV, UBCK, Bộ TN&MT với BĐS). Phải có counsel dedicated.
4. **Không port thẳng** từ ONFA fintech code — architecture assumption khác (Ohana = advisor, không hold funds).

---

## 7. Cross-cutting risks (mọi GĐ)

| Risk | Impact | Mitigation |
|---|---|---|
| **Multi-tenant data leak** (R1.22 analog) | HIGH — mất trust vĩnh viễn | `shop_id` scope SQL-level đã enforce Phase 2. Reviewer check mỗi patch touch `retrieval/*` / `db/*`. Soak-test GĐ3. |
| **Policy gate bypass** (auto-send không qua gate) | HIGH — reply sai tới khách | `agent/policy_gate.py` gate cứng. Reviewer check mỗi patch touch `agent/orchestrator.py`. SHADOW → hard-block sau ≥5 real decision. |
| **Financial rounding drift** (COD net lệch vài đồng) | MEDIUM — mất trust seller | Reconciliation script parity với raw carrier CSV, không tự sinh test data. |
| **Cross-border data (PDPD 13/2023)** | HIGH — regulatory | Legal counsel dedicated. Region hosting decision trước GĐ0 ship. |
| **Meta App Review delay** | MEDIUM — chặn GĐ2 | Submit cuối GĐ0. Có kế hoạch B nếu reject (Zalo-only pilot mở rộng). |
| **Recurring payment provider KYC delay** | MEDIUM — chặn GĐ3 | Evaluate ≥2 provider parallel, chốt sớm Spec 06a. |
| **RISK tier drift** (agent tự hạ tier) | HIGH — silent gate bypass | ADP hook enforce (floor rule: `files ∩ RISK_PATHS ≠ ∅ ⇒ ≥ medium`). |
| **Spec drift** (spec sửa mid-sprint) | HIGH — mất change-control | `adp_spec_lock_verify` chặn checkpoint nếu spec frozen bị sửa. |

---

## 8. Recommended execution order (tổng hợp)

```
Spec 03 (GĐ0 backfill)          — 2-3 tuần sau khi PRE-002/003/004 unblock
  ├─ Legal parallel: DPA + PDPD filing (Wyatt escalate)
  └─ Meta App Review submit ngay cuối Spec 03 (chuẩn bị GĐ2)
Spec 04a (order state + idempotency) — 1 tuần
Spec 04b (payment 1 provider)    — 1-2 tuần
Spec 04c (shipping 1 carrier)    — 1-2 tuần
  └─ [Unlock 150M #1 sau 4a-b-c acceptance]
Spec 04d (COD reconciliation)    — 1 tuần sau ≥5 đơn COD thật
Spec 05a (channel abstraction)   — 1 tuần
Spec 05b (FB Messenger)          — 2 tuần + Meta review wait
Spec 05c-d (multi-carrier + reconciliation) — 2 tuần
Spec 05e (analytics)             — 1-2 tuần
  └─ [Unlock 150M #2 sau 5a-e acceptance]
Spec 06a (recurring payment)     — 2-3 tuần
Spec 06b (subscription billing)  — 2 tuần
Spec 06c (reseller model)        — 1-2 tuần
Spec 06d (rate-limit + monitoring) — 1 tuần
Spec 06e (soak + load test)      — 1-2 tuần
Spec 06f (security audit)        — 2-4 tuần (external)
  └─ [Unlock 150M #3 sau 6a-f acceptance]
```

**Tổng critical path GĐ0→GĐ3 (nếu không có delay Meta/KYC):** ~22-32 tuần (~5-8 tháng).

---

## 9. Change log

| Date | Change | Author |
|---|---|---|
| 2026-07-17 | Initial draft — dựa trên spec 01 shipped + tranche map user cung cấp. Chưa Wyatt review. | Claude (main loop) |

---

*Roadmap này KHÔNG phải spec. Không có ADP:PHASE block. Mọi execution vẫn phải qua `docs/tasks/NN-Task-*.md` với spec-generator + ADP checkpoint. Roadmap chỉ là tổng quan để Wyatt priority + Tân biết thứ tự.*
