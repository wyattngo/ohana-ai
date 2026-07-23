---
gate_id: GD0-STEP4
derives_from: workflow#w-7.4-draftschema
approved_by: wyatt
approved_at: 2026-07-23
---

# GD0-STEP4 — Draft schema

## Target (Wyatt intent — đo được)

- Schema mang đủ: TTL, snapshot tầng 1, `persona_version_at_draft`, `label`, `escalation_reasons[]`, `status` có `sending`.
- `label` KHÔNG gộp vào `status` — `edited` phải capture được.

## Test policy (đã ký — hợp đồng bất biến; L2 spec sinh JIT phải tiêu thụ mỗi câu thành `GATE:` assertion)

- Cột tồn tại + nullable đúng; migration up→down→up trên Postgres **thật**.
- 2 approve đồng thời ⇒ 1 thành công, 1 nhận rows-affected = 0 (optimistic lock).
- Ghi `label` mỗi approve/reject/edit; `edited` phân biệt được với `approved`.
- **PRE-010 C3** — gia hạn TTL khi window còn < N ⇒ TTL = `window_end`, không vượt.

## Bound work items (ROADMAP §4)

- `GD0-DRAFTSCHEMA`
