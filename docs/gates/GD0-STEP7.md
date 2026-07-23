---
gate_id: GD0-STEP7
derives_from: workflow#w-7.7-draft-pipeline
approved_by: wyatt
approved_at: 2026-07-23
---

# GD0-STEP7 — Bộ soạn nháp

## Target (Wyatt intent — đo được)

- Tin khách → draft **giọng shop** → `policy_gate` → `PendingReply`.
- **Không nhánh GỬI** ở GĐ0 — mọi outcome là PARK hoặc PARK+ESCALATE.
- Draft không lộ Ohana.

## Test policy (đã ký — hợp đồng bất biến; L2 spec sinh JIT phải tiêu thụ mỗi câu thành `GATE:` assertion)

- E2E: tin khách → draft sinh; `intent`+`confidence` đến từ LLM, không hardcode.
- Regex trên **output THẬT** (không phải prompt): không chứa 'Ohana' / 'trợ lý ảo' / 'tôi là AI'.
- Assert **không outcome nào = send** — `auto_send` chặn cứng ở GĐ0.
- Tầng 1 API fail ⇒ ESCALATE `data_unavailable`, KHÔNG draft.
- Media ⇒ auto-ESCALATE `media_content`, không gọi LLM.
- Import-graph: `Drafter` KHÔNG tự gọi sender.

## Bound work items (ROADMAP §4)

- `GD0-DRAFTER`
- `GD0-HISTORY`
- `GD0-POLICY`
- `GD0-TOOLS` *(weak)*
