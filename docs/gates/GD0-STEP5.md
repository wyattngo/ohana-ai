---
gate_id: GD0-STEP5
derives_from: workflow#w-7.5-shop-profile
approved_by: null
approved_at: null
---

# GD0-STEP5 — Hồ sơ shop

## Target (Wyatt intent — đo được)

- Persona có version + cổng duyệt; chưa duyệt ⇒ dùng persona mặc định.
- Tri thức tầng 2 tra bằng **hàm tất định**, không RAG.
- Trần token enforce **lúc save**, không truncate lúc build prompt.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] `lookup_size(160,50) == "M"` — assert thật, KHÔNG LLM-as-judge.
- [ ] Thiếu data ⇒ trả `not_found` tường minh (tín hiệu này nuôi cổng chính sách).
- [ ] Persona chưa duyệt ⇒ prompt dùng persona mặc định.
- [ ] Vượt trần token ⇒ chặn **lúc save**; không có đường truncate lúc build.
- [ ] Save version mới ⇒ cache `(shop_id, version)` invalidate.

## Bound work items (ROADMAP §4)

- `GD0-SHOPS`
