---
gate_id: GD0-STEP6
derives_from: workflow#w-7.6-cost-cap
approved_by: wyatt
approved_at: 2026-07-23
---

# GD0-STEP6 — Cost cap pre-charge + persistent debounce scheduler

## Target (Wyatt intent — đo được)

- Pre-charge **trước** call, reconcile sau khi có token count thật.
- Chạm cap ngày ⇒ mọi tin còn lại PARK, **không gọi LLM**.
- Debounce timer sống qua worker restart.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] Pre-charge reserve trước call; reconcile giải phóng phần dư.
- [ ] Chạm cap ⇒ `policy_gate` PARK **và** assert LLM KHÔNG được gọi.
- [ ] Gọi API trực tiếp (bypass UI) vẫn bị trừ credit.
- [ ] Worker crash giữa lúc debounce ⇒ scheduler vẫn bắn (đọc lại từ DB).
- [ ] **PRE-010 C2** — 2 scheduler song song cùng conversation ⇒ đúng 1 draft.

## Bound work items (ROADMAP §4)

- `GD0-METER`
