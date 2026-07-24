# Human Sync Review (RISK:high) — bound to diff

diff_sha256: 18f93914eef78c2da13e5253ff4281bba7bc7b3b2abcbf1a58e2a5b673aa3e9b
generated: 2026-07-24T22:05
repo: .

> Đọc `git -C "." diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
- Wyatt xác nhận diff P1 OK (2026-07-24). Claude trình bày nguyên văn diff signature.py +
  webhook.py + repos.py + tests; Wyatt review và duyệt.
- KHÔNG chạm money/balance/commission — P1 là security boundary (signature verify), 3 trục
  money-code không áp dụng ở phase này.
- Trục auth/session: verify TRƯỚC parse enforced (test parse_count=0 khi verify fail); key =
  OA Secret per-OA (không App Secret); fail-loud 501 khi adapter thiếu verify_signature.
- Trục side-effect: verify chạy read-only (1 short-lived session lookup secret), không ghi DB
  không gọi ngoài. parse_inbound chỉ chạy sau verify PASS.
- Comment drift trong channels/zalo/__init__.py (docstring nói "core skip verify" — sai sau
  HIGH 1 fix) đã Claude phát hiện lúc đọc diff + sửa; diff re-stamped 18f93914eef7.
- Confused-deputy gap (HIGH 2) chấp nhận defer P4 — chỉ materialize khi mount (enabled=True),
  P4 BLOCKED nên chưa có rủi ro thật hôm nay.
