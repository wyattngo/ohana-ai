---
gate_id: GD0-STEP3
derives_from: workflow#w-7.3-rules-intent
approved_by: wyatt
approved_at: 2026-07-23
---

# GD0-STEP3 — Rules layer intent nhạy cảm

## Target (Wyatt intent — đo được)

- Intent nhạy cảm quyết bằng **rules**, KHÔNG bằng `confidence` do LLM tự khai.
- Multi-match cho kết quả **tất định**.
- `injection_attempt` là intent hạng nhất, không phải phụ lục.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] 5–6 nhóm nhạy cảm match đúng: khiếu nại/hoàn tiền/dọa kiện · 'có phải bot' · luật/cơ quan · injection.
- [ ] Multi-match ⇒ ESCALATE thắng; `escalation_reasons[]` chứa **mọi** intent match được.
- [ ] **PRE-010 C5** — hoán vị thứ tự rule ⇒ intent chọn ra KHÔNG đổi.
- [ ] Import-graph: không đường nào đọc LLM confidence để quyết gate.

## Bound work items (ROADMAP §4)

- `GD0-INTENT`
