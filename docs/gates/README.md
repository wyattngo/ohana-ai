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
2. **Test policy** — danh sách câu **hành vi đo được** đã ký, bất biến sau khi Wyatt sign.
   Đây KHÔNG phải checklist state — nó là **hợp đồng** cho tác giả spec L2 sinh JIT: mỗi
   câu chuyển thành 1 assertion trong `GATE:` của phase tương ứng.
3. **Bound work items** — ID ở `ROADMAP.md §4` mà gate này chi phối.

## Quy tắc

- **CC propose, Wyatt sign.** File sinh ra với `approved_by: null` / `approved_at: null`.
  Gate **chưa ký thì không bind** work item — không dùng nó biện minh cho việc code.
- **1 gate = 1 anchor `§7.x`.** `derives_from` trỏ anchor có thật; `verify_derives` kiểm.
- **Đóng gate** = mọi phase L2 dẫn xuất từ work item bound có `STATUS: DONE` — tức
  `GATE:` của từng phase pass thật qua `adp-checkpoint.sh` + EVIDENCE + hash khớp diff.
  KHÔNG có ô tick nào ở tầng này. Nội dung `Test policy` được chuyển vào `GATE:` khi L2 sinh
  (DEC-OHANA-06). Sửa nội dung câu = cần DEC riêng, KHÔNG patch lặng.

## Trạng thái

9 gate ↔ 9 sub-step `§7.1`–`§7.9`. **Tất cả đã ký — `approved_by: wyatt`, `approved_at: 2026-07-23`.**
Gate đã ký ⇒ **bind** work item; từ đây một task chạm `GD0-*` phải đóng được Tests của
gate tương ứng, không phải chỉ "code xong là done".

**`GD0-STEP8` (DPIA) — ký theo option (a), Wyatt 2026-07-23.** Gate này **cố ý không
bind work item nào**: nó là nửa **external** của `GD0-PII` (filter internal ở `w-7.2`,
DPIA là filing pháp lý ở `w-7.8`). Hệ quả đã chấp nhận: DPIA **vẫn là điều kiện ship**
nhưng **không vào mẫu số** `internal` — nó không đo tiến độ, nó chặn cửa.
Option (b) — đẻ ID riêng cho DPIA — bị bỏ vì cần DEC (§9.4) cho một mục mà tiến độ
nằm ngoài tay đội.

⚠️ Một gate đã ký **không** có nghĩa Test policy đã pass. Ký = "đây đúng là điều kiện tôi
muốn cho sub-step §7.n" — bất biến sau khi ký. Đóng gate = mọi phase L2 dẫn xuất
`STATUS: DONE` qua `adp-checkpoint.sh`. Đừng lẫn hai việc (DEC-OHANA-06).

⚠️ **`GD0-RESIDENCY` token phase (ADR §4 / F4) CHƯA land.** Cơ chế đã chốt — 1 phase
block `ROADMAP: GD0-RESIDENCY` với gate grep-only trên
[`2026-07-18-hosting-region.md`](../adr/2026-07-18-hosting-region.md) (đã `ACCEPTED`).
Chưa đặt vào spec nào vì **L2 sinh JIT** — chờ spec compliance ra đời, không dựng spec
rỗng chỉ để chứa một token phase.
