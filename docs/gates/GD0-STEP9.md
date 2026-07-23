---
gate_id: GD0-STEP9
derives_from: workflow#w-7.9-corpus-luong-a
approved_by: null
approved_at: null
---

# GD0-STEP9 — Nối corpus nền tảng vào Luồng A

## Target (Wyatt intent — đo được)

- Corpus nền tảng ingest được; `search_wiki` trả chunk **đúng chủ đề**.
- Không tra được đoạn nào ⇒ **nói không biết**, không trả lời chay.
- Luồng A không chạm dữ liệu shop.

## Tests (PHẢI tồn tại TRƯỚC khi bắt tay task)

- [ ] Ingest corpus thật → `search_wiki` trả chunk đúng chủ đề — kiểm **THỨ HẠNG**, không chỉ 'có trả về'.
- [ ] Không có chunk liên quan ⇒ trả 'không biết'; assert không bịa.
- [ ] Câu hỏi user được wrap `<user_question>` (§7.2 áp cả Luồng A).
- [ ] Import-graph: Luồng A không đọc/ghi dữ liệu shop.

## Bound work items (ROADMAP §4)

- `GD0-WIKI`
- `GD0-EMBED`
- `GD0-CHAT`
