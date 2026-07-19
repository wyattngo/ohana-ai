# Human Sync Review (RISK:high) — bound to diff

diff_sha256: 3dab502233818e795f0fe5fac2e359f57c62c721a4837ea288c6e3e3555c0837
generated: 2026-07-19T23:10
repo: /Users/wyattngo/Sites/localhost/ohana-ai

> Đọc `git -C "/Users/wyattngo/Sites/localhost/ohana-ai" diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
- Duyệt 2026-07-19. **Duyệt trên TÓM TẮT do Claude trình bày, KHÔNG đọc từng dòng `git diff HEAD`.**
  Ghi đúng như vậy để người đọc sau biết chữ ký này nặng đến đâu — nó KHÔNG tương đương một
  vòng đọc diff đầy đủ.
- Nội dung đã xem và xác nhận, theo 3 trục của stub:
  1. tiền/số dư/commission: KHÔNG chạm (Ohana không có money code).
  2. auth/session: KHÔNG chạm.
  3. side-effect: `DELETE FROM embeddings` + `ALTER TYPE vector(1024)`. Hôm nay xoá 0-2 row
     test fixture; corpus thật chưa land (PRE-003). `downgrade` CŨNG xoá — reversible về
     schema, KHÔNG về dữ liệu. Không FK nào trỏ tới `embeddings`. Index `idx_emb_shop_ns`
     sống sót (smoke thật).
- Đổi hành vi runtime: `default_embedder()` ưu tiên `TogetherEmbedder`. Nhánh `OpenAIEmbedder`
  (1536) giữ lại, dùng nhầm thì Postgres từ chối — verify không có try/except nuốt exception.
- Reviewer tự động vòng 1 trả NEEDS_REVIEW: migration thiếu guard cơ học, chỉ có docstring
  cảnh báo. ĐÃ VÁ trước khi ký: `_SAFE_ROW_THRESHOLD=10` + env override, kèm test bắn thật cả
  hai vế (chặn khi vượt ngưỡng · cho chạy khi có override).
- PRE-E04 (xoá vector cũ) do chính Wyatt ký cùng ngày, sau khi verify sống bảng còn 2 row.
- **Về việc artifact này được tạo lại:** bản đầu bound vào diff `b9cc768ac4c2`. Sau đó hash đổi
  thành `3dab502233818e` vì Claude ghi thêm 2 dòng `SMOKE:`/`REVIEW:` vào phase block — đúng
  thứ tự bắt buộc (ghi dòng TRƯỚC, stamp SAU) mà lần đầu làm ngược. Xác định delta bằng cách đo,
  không phỏng đoán: `docs/reviews/` được LOẠI khỏi phép băm (kiểm bằng probe), nên phần thay đổi
  duy nhất giữa hai hash là 2 dòng bookkeeping trong spec. **KHÔNG có dòng code nào đổi kể từ lúc
  duyệt.** Nội dung Wyatt xác nhận vẫn nguyên giá trị.
