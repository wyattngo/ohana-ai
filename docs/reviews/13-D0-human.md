# Human Sync Review (RISK:high) — bound to diff

diff_sha256: 7db0d49369b60f3df5e49910fce0b005e3483d78e76a49518f020069f70f6832
generated: 2026-07-21T15:03
repo: /Users/wyattngo/Sites/localhost/ohana-ai

> Đọc `git -C "/Users/wyattngo/Sites/localhost/ohana-ai" diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
VERDICT: APPROVE
NOTES:
- Sync review qua main-loop (Wyatt ký APPROVE 2026-07-21). 3 trục kiểm:
  1. amount/số dư/commission: N/A — D0 không chạm tiền; nhưng `confidence` Drafter lái auto_send,
     đã xác nhận không bịa (`_parse_emit_reply` raise nếu thiếu `emit_reply`; live smoke thấy model
     thật gọi tool).
  2. auth/session: `shop_id` từ param `draft()` (verified upstream), KHÔNG từ LLM/body; `emit_reply`
     schema `additionalProperties:false` chặn LLM nhét `shop_id`; `ShopProfileRepo(shop_scope=)` SQL-level.
  3. side-effect: drafter KHÔNG có đường gửi khách — test `test_drafter_module_cannot_reach_the_send_path`
     đi bao đóng AST enforce (không import sender/channels/policy_gate/orchestrator).
- Auto-verdict Haiku: APPROVE, 0 finding. Đồng ý.
- Ghi nhận follow-up (không chặn D0): `tool_choice` không ép — theo dõi flaky ở D1, ép nếu cần.
