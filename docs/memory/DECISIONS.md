# DECISIONS — Ohana AI Seller

> Signed decision log. Mỗi quyết định = 1 entry immutable. Rationale MUST include: alternatives considered + why chosen + consequences. Wyatt approve = ghi "SIGNED-BY: Wyatt · <YYYY-MM-DD>".
>
> Format lấy cảm hứng ADR (Architecture Decision Record) — nhưng scope rộng hơn: cả architectural + product + workflow decisions.

---

## Entry format

```
### DEC-NNN — <short title>
- **Date:** <YYYY-MM-DD>
- **Status:** PROPOSED | ACCEPTED | SUPERSEDED (by DEC-MMM) | REJECTED
- **Signed-by:** Wyatt · <YYYY-MM-DD>   (chỉ ghi khi ACCEPTED)
- **Context:** <what triggered this decision — link ISSUE-NNN nếu có>
- **Options considered:**
  1. <option A> — pros / cons
  2. <option B> — pros / cons
  3. <option C> — pros / cons
- **Decision:** <chọn option nào, phrase 1 câu quyết đoán>
- **Rationale:** <why — reference priority order safety→trust→stability→growth khi relevant>
- **Consequences:**
  - <what changes as a result>
  - <what phase/spec must update>
- **Supersedes:** <DEC-MMM nếu có, hoặc "none">
```

---

## Pending — chờ Wyatt sign (block Phase 1.0 / Phase 2)

### DEC-001 — Channel đầu = Zalo OA (hay Meta/FB)
- **Date:** 2026-07-16
- **Status:** PROPOSED
- **Signed-by:** — (waiting Wyatt)
- **Context:** ISSUE-001. Memory note "Zalo-first recommended" nhưng chưa lock. Sub-task D/E (bridge) depend vào quyết định này.
- **Options considered:**
  1. **Zalo OA first** — pros: rate-limit rõ (48h/8-msg window), API stable, VN-native seller quen. cons: rate-limit khắt khe hơn Meta, cần policy_gate mạnh.
  2. **Meta/FB Messenger first** — pros: reach lớn hơn, không rate-limit 48h. cons: API churn nhiều, ToS strict về automation, ecosystem docs kém hơn.
  3. **Cả hai parallel** — cons: scope Phase 3 GĐ0 MVP không kham nổi (3-4 tuần).
- **Decision:** _pending_
- **Rationale:** _pending_
- **Consequences:**
  - Phase 4 (Sub-task D/E) target bridge sẽ pin theo channel này.
  - Rate-limit + policy_gate design ở Phase 5 depend vào channel constraint.
- **Supersedes:** none

### DEC-002 — Cardinality tenant: `shop_id` đủ vs cần `seller_id`+`tenant_id`
- **Date:** 2026-07-16
- **Status:** PROPOSED
- **Signed-by:** — (waiting Wyatt)
- **Context:** ISSUE-002. Critical trước Phase 2 (tenant-first `db/models.py`). Sai schema đầu Phase 2 = R1.22 analog (multi-tenancy retrofit rủi ro nhất).
- **Options considered:**
  1. **Single `shop_id`** — pros: simple, index nhanh, query đơn giản. cons: nếu 1 seller có nhiều shop → không distinguish, phải retrofit.
  2. **`(seller_id, shop_id)` composite** — pros: cover use case 1 seller nhiều shop từ đầu. cons: mọi query + FK phải include 2 cột, complexity ×2.
  3. **`tenant_id` (org level) + `shop_id`** — pros: mở đường B2B agency (agency quản nhiều seller nhiều shop). cons: over-engineering nếu GĐ0 chỉ cần solo seller.
- **Decision:** _pending_
- **Rationale:** _pending_
- **Consequences:**
  - Phase 2 `db/models.py` schema design pin theo lựa chọn này.
  - JWT claim shape (`auth/jwt.py`) phải khớp — port từ DrNick sẽ khác đáng kể tuỳ chọn.
  - Retrieval pgvector namespace scope (Phase 2) dùng cùng key.
- **Supersedes:** none

### DEC-003 — RISK tier finalize cho spec 02 §13
- **Date:** 2026-07-16
- **Status:** PROPOSED
- **Signed-by:** — (waiting Wyatt)
- **Context:** Spec 02 §13 tracking hiện `low/low/medium/medium` proposed. Cần Wyatt sign trước Phase 1.0 kick-off — RISK tier quyết định governance flow (auto vs ANCHOR confirm vs per-step).
- **Options considered:**
  1. **Giữ nguyên proposed** (1.0=low, 1.1=low, 1.2=medium, 1.3=medium) — pros: floor rule tự áp cho 1.2/1.3 (chạm RISK_PATHS). cons: 1.1 skeleton create pyproject/app/tests — không chạm RISK_PATHS thật nhưng shape toàn repo, có thể muốn bump lên medium.
  2. **Bump 1.1 lên medium** — pros: 1 ANCHOR confirm cho skeleton là hợp lý (blast radius = toàn repo). cons: chậm hơn.
  3. **Bump toàn bộ lên medium** — pros: uniform. cons: 1.0 chỉ read-only, low là đúng.
- **Decision:** _pending_
- **Rationale:** _pending_
- **Consequences:**
  - Session sau đọc tier từ `<!-- ADP:PHASE X.Y -->` block khi chạy `adp-checkpoint.sh`.
- **Supersedes:** none

---

## Accepted (chưa có)

_Empty. Khi Wyatt sign 1 PROPOSED entry, di chuyển vào đây kèm SIGNED-BY line._

---

## Superseded (chưa có)

_Empty. Khi 1 DEC bị 1 DEC mới thay thế, di chuyển vào đây (giữ nội dung gốc, thêm "Superseded by: DEC-MMM · <date>" ở đầu)._

---

## Rejected (chưa có)

_Empty._

## DEC-OHANA-02 — Model General Chat (2026-07-19)

Giữ `meta-llama/Llama-3.3-70B-Instruct-Turbo`. KHÔNG đổi sang `MiniMaxAI/MiniMax-M3`.

Đo n=6 trên ca an toàn ("chưa kết nối kho, khách hỏi mấy ngày ship"): MiniMax bịa số ngày
**6/6**, Llama **0/6**. Chi phí THẬT: MiniMax $0.554/1000 tin vs Llama $0.234 — MiniMax rẻ
hơn 3.5× trên bảng giá nhưng đắt hơn 2.4× khi dùng, vì nói dài gấp 4.5×.

**So model bằng `$/1M token` là so sai đơn vị** — đơn vị đúng là `$/việc hoàn thành`.

Chi tiết + cách tái lập: `docs/decisions/DEC-OHANA-02-chat-model-selection.md`.

## DEC-OHANA-05 — `backend-workflow.md` là cấu trúc code chính thức (2026-07-21)

- **Status:** ACCEPTED
- **Signed-by:** Wyatt · 2026-07-21
- **Context:** Wyatt xem xét lại và chốt `docs/backend-workflow.md` (mô tả luồng backend hai persona) làm **quyết định cấu trúc code chính thức**. Audit trước đó phát hiện 6 điểm workflow lệch với L1 `ROADMAP.md`, và code đang bám L1.
- **Decision:** Workflow doc là nguồn cấu trúc code authoritative. **Khi L1 và workflow lệch → workflow thắng.** L1 v6 hoà giải, KHÔNG phá vỡ hiện trạng (không đụng code/L2 spec).
- **Rationale:** Một nguồn cấu trúc duy nhất; các cú đặt cược an toàn của workflow (idempotency-first, snapshot bắt buộc, label-day-1, no-auto-send GĐ0, gate không tin LLM confidence, two-service, PII filter) khớp priority order safety→trust→stability→growth.
- **Consequences:**
  - L1 v6: thêm `GD0-INGEST` (tách idempotency internal khỏi `GD0-ZALO`), `GD0-DRAFTSCHEMA`, `GD0-SPLIT`, `GD0-PII`, `GD0-COALESCE`; siết `GD0-POLICY`/`GD0-DRAFTER`/`GD0-METER`/`GD0-HISTORY`; append-only (không rename/xoá ID).
  - Mẫu số `internal` GĐ0 tăng +5 (% giảm honest, §0.2).
  - Code chưa đổi — hành vi (chặn auto_send, snapshot, last-N=6, idempotency) land qua ADP spec riêng, RISK tier do Wyatt gán.
  - Hai tài liệu-doc-conflict cần Wyatt xác nhận sequencing: `GD0-SPLIT` (two-service) đặt pre-prod; last-N 6-vs-20 reconcile về 6.
- **Supersedes:** none (bổ sung; không thay DEC nào)

