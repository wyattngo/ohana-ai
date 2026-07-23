---
gate_id: GD0-STEP1
derives_from: workflow#w-7.1-webhook
approved_by: wyatt
approved_at: 2026-07-23
---

# GD0-STEP1 — Webhook + outbox + binding + queue

## Target (Wyatt intent — đo được)

- Webhook trả **200 ≤ 2s** và LLM KHÔNG chạy trong request path.
- `shop_id` chỉ đến từ `wiho_shop_channel_binding` đã `verified_at`, không bao giờ từ body chưa verify.
- Nhận lại cùng `(channel, platform_msg_id)` ⇒ đúng **1** row `webhook_seen` **và** đúng **1** row `outbox`.

## Test policy (đã ký — hợp đồng bất biến; L2 spec sinh JIT phải tiêu thụ mỗi câu thành `GATE:` assertion)

- ACK < 2s; assert không có LLM call nào trong request path.
- Signature fail ⇒ từ chối, KHÔNG ghi row nào.
- Binding không tìm thấy ⇒ 200 + log, **KHÔNG** enqueue.
- 2 webhook đồng thời cùng key ⇒ 1 `webhook_seen` **VÀ** 1 `outbox` (chứng minh CTE+RETURNING, không phải 2 INSERT rời).
- **PRE-010 C1** — deliver cùng event 2 lần ⇒ đúng 1 message row (dedup key).

## Bound work items (ROADMAP §4)

- `GD0-INGEST`
- `GD0-ZALO` *(weak)*
- `GD0-COALESCE` *(weak)*
- `GD0-WINDOW` *(weak)*
