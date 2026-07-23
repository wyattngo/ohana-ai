# Tầng Gate — binding layer của derivation pipeline

ADR [`2026-07-22-derivation-pipeline`](../adr/2026-07-22-derivation-pipeline.md).

```
backend-workflow.md  (WHY + shape — Wyatt viết, anchors)
    ↓ derives
docs/gates/          ← BẠN Ở ĐÂY (target + test policy)
    ↓ contracts
ROADMAP.md §4        (work item + derives_from)
    ↓ triage
docs/tasks/          (L2 spec — sinh JIT khi code)
```

## Gate là gì

Một gate = **một sub-step của workflow §7**, mang ba thứ:

1. **Target** — ý định của Wyatt, viết ở dạng **đo được**. Không phải mô tả tính năng.
2. **Tests** — phải tồn tại **TRƯỚC** khi bắt tay task. Đây là điểm khác biệt: test
   không phải sản phẩm phụ của code, nó là **hợp đồng** viết trước.
3. **Bound work items** — ID ở `ROADMAP.md §4` mà gate này chi phối.

## Quy tắc

- **CC propose, Wyatt sign.** File sinh ra với `approved_by: null` / `approved_at: null`.
  Gate **chưa ký thì không bind** work item — không dùng nó biện minh cho việc code.
- **1 gate = 1 anchor `§7.x`.** `derives_from` trỏ anchor có thật; `verify_derives` kiểm.
- **Đóng gate** = mọi ô `[ ]` trong *Tests* tick xong bằng test chạy thật, không phải lời khai.

## Trạng thái

9 gate ↔ 9 sub-step `§7.1`–`§7.9`. **Tất cả đang `approved_by: null`** — chờ Wyatt ký từng file.

⚠️ **`GD0-STEP8` (DPIA) chưa có work item nào bind.** Đây là nửa **external** của
`GD0-PII` (filter là internal `w-7.2`, DPIA là filing pháp lý `w-7.8`). Hai lựa chọn,
Wyatt quyết: (a) chấp nhận gate không bound — nó vẫn là điều kiện ship; hoặc (b) đẻ ID
mới cho DPIA (cần DEC theo ROADMAP §9.4).

⚠️ **`GD0-RESIDENCY` token phase (ADR §4 / F4) CHƯA land.** Cơ chế đã chốt — 1 phase
block `ROADMAP: GD0-RESIDENCY` với gate grep-only trên
[`2026-07-18-hosting-region.md`](../adr/2026-07-18-hosting-region.md) (đã `ACCEPTED`).
Chưa đặt vào spec nào vì **L2 sinh JIT** — chờ spec compliance ra đời, không dựng spec
rỗng chỉ để chứa một token phase.
