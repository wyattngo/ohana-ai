# Human Sync Review (RISK:high) — bound to diff

diff_sha256: c31f127444021440a9c5440a751311f8439c9444c477e30e2dc9f29658dacf95
generated: 2026-07-17T09:06
repo: .

> Đọc `git -C "." diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
- Ohana không phải wallet — 3 trục dịch sang: (1) auto-send-to-customer flow, (2) auth + tenant scope, (3) side-effect (DB, network). Phase 5 là "acceptance-blocking" surface: policy gate + park-vs-send.
- Trục 1 (auto-send flow): agent/orchestrator.py:receive_and_draft có ĐÚNG 1 nhánh gọi sender.send() — sau decide().action=="auto_send". Nhánh park chỉ ghi PendingReplyRepo.create(), KHÔNG chạm sender. Không có shortcut/back-door.
- Precedence guard: policy_gate.decide() theo thứ tự cứng — sensitive_intent → low_confidence → auto_disabled → send. Test test_sensitive_intent_always_parks_even_with_high_confidence_and_auto_enabled (unit) + test_sensitive_intent_parks_and_never_sends (orchestrator adversarial) đều assert: confidence=0.99 + shop_auto_enabled=True + intent=refund → park. SENSITIVE_INTENTS = frozenset ({"complaint","refund","price_negotiation","specific_order"}); test_sensitive_intents_frozen assert .add() raises AttributeError. DEFAULT_CONFIDENCE_THRESHOLD=0.85 (>= 0.8 test-locked).
- Trục 2 (auth + tenant): PendingReplyRepo(shop_scope=…) bắt buộc, empty reject. create() bake shop_id từ scope, không nhận shop_id arg. mark_decided() SQL WHERE shop_id==scope AND reply_id==:id AND status IN (pending, approved). test_sensitive_intent_parks_and_never_sends có adversarial: PendingReplyRepo(s, shop_scope="shop_b").list_pending() → [] (không thấy shop_a row). api/webhook.py enabled=False mặc định → 503 (không bao giờ nhận webhook trong prod cho tới khi PRE-004 clear); shop_id lookup từ oa_id path param qua oa_to_shop map, KHÔNG từ body. api/inbox.py 3 route đều Depends(identity_dep) → Identity.shop_id; không lấy scope từ URL/body/query.
- Trục 3 (side-effect): bridge/zalo_sender.py mặc định MockZaloSender (log only, no network) — real HTTP sender defer PRE-004. Alembic 0002 chỉ tạo 1 bảng pending_reply với composite index (shop_id, status, created_at); downgrade đảo ngược đầy đủ. PendingReplyRepo.mark_decided await self._session.commit() — atomic per-request. Không cron, không background job trong phase này.
- Deferred (không blocker Phase 5, ghi lại cho Phase 3+):
  - Zalo signature verify TODO đã comment trong api/webhook.py line "TODO(PRE-004)".
  - `oa_to_shop` là in-memory dict — thay bằng shops table khi wider schema landed.
  - `shop_auto_enabled` per-shop config vẫn in-memory — sẽ landed vào shops table.
  - Send-on-approve worker (drain approved rows → sender.send()) chưa có — theo docstring api/inbox.py là "separate worker Phase 3+". API approve/reject chỉ flip status; outbound send chưa được wire → phải nhớ khi PRE-004 clear.
  - Full inbox UI framework (spec §12 [UNVERIFIED] web/) chưa có; chỉ REST scaffold.
  - Real Drafter (Protocol) implementation với F1+F2 context enrichment chưa có — orchestrator tính là "glue only", drafter thật land ở phase 6+ hoặc backfill.
- Verdict: match auto-verdict (APPROVE). concerns: [].
