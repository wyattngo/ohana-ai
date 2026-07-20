# Human Sync Review (RISK:high) — bound to diff

diff_sha256: 2d8a1124183104bba2912d44404730e2bb97cb5e4d447b0af72e22f8a653ece1
generated: 2026-07-20T23:14
repo: /Users/wyattngo/Sites/localhost/ohana-ai

> Đọc `git -C "/Users/wyattngo/Sites/localhost/ohana-ai" diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
REBIND: hash cũ 232971ed6393 → 2d8a11241831. Lý do DUY NHẤT: flip `STATUS: TODO → IN_PROGRESS`
  của chính phase này trong spec (Claude quên flip trước khi làm). KHÔNG dòng code nào đổi —
  `git diff` giữa hai hash chỉ là một từ trong file spec. Review của Wyatt vẫn áp đúng code đã đọc.
REVIEWED_AT: 2026-07-20 (sync, trong phiên — Wyatt đọc `git diff HEAD` rồi xác nhận "ok")
NOTES:
- Wyatt đọc diff đồng bộ và DUYỆT. Ghi chép dưới đây do Claude soạn theo yêu cầu của Wyatt
  ("điền notes") — phần được Wyatt xác nhận là **quyết định duyệt**, không phải từng dòng phân tích.
- Phạm vi đã trình bày trước khi duyệt (3 trục của stub):
  · tiền/số dư/commission — KHÔNG áp dụng: Ohana chưa có cột tài chính nào trong toàn repo.
  · auth/session — trọng tâm phase. `verify_token` GIỮ NGUYÊN sync/thuần (không kéo DB vào
    verify chữ ký). Tầng mới `build_active_shop_dep` đối chiếu `shops`, `build_admin_dep`
    kiểm shop TRƯỚC role. Đủ 3 call site: inbox / chat / admin.
  · side-effect — `POST /admin/shops` ghi bảng `shops` (admin-only, id do server sinh);
    `mock_authorize` seed fixture shop, nằm SAU `_is_dev_env()` và `on conflict do nothing`.
- Quyết định đã ký trước đó, phase này thi hành: `status != 'active'` ⇒ 401 (fail-closed);
  CHƯA cache tra `shops`.
- Mở rộng ALLOWED_FILES đã duyệt riêng trong phiên: `db/shop_repo.py` (gate import-graph spec 07
  bắt buộc tách), `app/main.py`, `api/inbox.py`, `api/chat.py` (annotation async — mypy ép).
- Nợ ghi nhận, KHÔNG chặn checkpoint: onboard chỉ có `require_admin` bảo vệ; khi có nhiều
  admin thật thì đường sinh tenant này cần audit log riêng.
