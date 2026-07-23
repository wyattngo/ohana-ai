---
gate_id: GD0-STEP2
derives_from: workflow#w-7.2-pii-filter
approved_by: null
approved_at: null
---

# GD0-STEP2 — PII filter + injection defense wrapping

## Target (Wyatt intent — đo được)

- **Không payload nào** tới LLM mà chưa qua filter — tin khách, lịch sử, **kết quả tool tầng 1**, trường persona.
- Mọi user-generated content nằm trong tag (`<customer_message>` / `<user_question>`).
- Filter lỗi ⇒ **fail-closed**: không gọi LLM.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] Regex bắt: SĐT VN (03/05/07/08/09), CCCD 9 và 12 số, STK 8–19 số, email, địa chỉ.
- [ ] **Kết quả tầng 1** (`order_status` trả địa chỉ + SĐT người nhận) BỊ lọc — không chỉ tin khách.
- [ ] Prompt build ⇒ user content luôn được wrap; không có đường bypass.
- [ ] Filter raise ⇒ assert LLM call KHÔNG xảy ra.
- [ ] **PRE-010 C4** — script đo FN rate trên tập gán nhãn ≥200 tin, ra **con số**.

## Bound work items (ROADMAP §4)

- `GD0-PII`
