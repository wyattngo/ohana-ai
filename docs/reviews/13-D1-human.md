# Human Sync Review (RISK:high) — bound to diff

diff_sha256: a3417442de0c97e9777c208e0d69cef7b6b7356f104c7d33a7afe9634ce14c6d
generated: 2026-07-21T15:29
repo: /Users/wyattngo/Sites/localhost/ohana-ai

> Đọc `git -C "/Users/wyattngo/Sites/localhost/ohana-ai" diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
VERDICT: APPROVE
NOTES:
- Sync review qua main-loop (Wyatt ký APPROVE 2026-07-21). 3 trục kiểm:
  1. amount/số dư/commission: N/A — D1 không chạm tiền.
  2. auth/session (multi-tenant): `_dispatch` truyền `shop_id` từ param `draft()` (verified) xuống
     `tool.handler(customer_id, shop_id, args)`, KHÔNG từ `tc.arguments` (LLM). Test tiêm
     `shop_id="BOGUS"` vào args ⇒ bị bỏ, handler nhận shop thật. `additionalProperties:false` chặn.
  3. side-effect (gọi ngoài): tool-loop gọi `lookup_size`/`lookup_shipping` (read, scope shop_id).
     Drafter vẫn KHÔNG có đường gửi khách — import-graph gate D0 còn hiệu lực (không import
     sender/policy_gate/orchestrator/channels; thêm `tools.registry` không kéo forbidden nào).
- 2 RETRY do smoke bắt (finalize + grounding directive) — cả hai fix in-scope agent/drafter.py,
  live smoke chứng minh grounding thật (XL3). Đồng ý.
- Ghi nhận follow-up (KHÔNG chặn D1): grounding hiện mềm ở tầng prompt. Hàng rào cứng
  (tool_choice="required" / eval bắt câu ungrounded) để GD0-EVAL / GD0-INTENT. Auto-verdict Haiku
  APPROVE 0 finding — đồng ý.
