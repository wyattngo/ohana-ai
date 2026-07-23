---
gate_id: GD0-STEP8
derives_from: workflow#w-7.8-dpia
approved_by: null
approved_at: null
---

# GD0-STEP8 — DPIA cross-border

## Target (Wyatt intent — đo được)

- DPIA hoàn tất **per-provider** trước khi rời sandbox.
- Destination của mọi LLM call được log cho audit.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] Gate **grep-only**: file DPIA tồn tại + frontmatter `status: ACCEPTED` (không content-check — ADR §4).
- [ ] Mọi LLM call có destination log; assert không call nào thiếu.

## Bound work items (ROADMAP §4)

- *(chưa có ID bind — đây là nửa **external** của `GD0-PII`; xem ghi chú dưới)*
