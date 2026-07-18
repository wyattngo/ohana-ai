# Human Sync Review (RISK:high) — bound to diff

diff_sha256: f4bc655d650bbb1dab85bc94d2707d3eb40e3f1e184a25023a4af7e32b8361a7
generated: 2026-07-18T12:28
repo: .

> Đọc `git -C "." diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
-
