# Human Sync Review (RISK:high) — bound to diff

diff_sha256: 0e1e61c9f89f841e52208ec026258efbd7b62d35e013f25bf3567f7c790423e1
generated: 2026-07-17T08:17
repo: .

> Đọc `git -C "." diff HEAD`. Xác nhận 3 trục money-code:
>   1. amount / số dư / commission   2. auth / session   3. side-effect (ghi DB, gọi ngoài)
> Review XONG đúng diff này → giữ nguyên diff_sha256 ở trên, điền NOTES, giữ dòng REVIEWED_BY.
> Nếu diff đổi sau khi tạo file này, checkpoint sẽ REFUSE (hash lệch) — tạo lại.

REVIEWED_BY: wyatt
NOTES:
- Ohana không phải wallet — 3 trục dịch sang: (1) tenant scope, (2) auth, (3) side-effect. Không có money code trong diff.
- Trục 1 (tenant scope): Message.shop_id + Embedding.shop_id đều nullable=False cả ở ORM và migration 0001. Index dẫn đầu bằng shop_id (idx_msg_shop_created, idx_emb_shop_ns). PgvectorRetriever.__init__ nhận shop_scope kw-only bắt buộc, empty string bị reject. SQL WHERE shop_id == shop_scope + namespace IN (…) áp dụng TRƯỚC order_by(dist).limit(k) — không post-filter. Test 2 xác nhận: shop_b vector gần hơn nhưng bị loại. Không có bypass path; wildcard "*" chỉ hits rỗng, không phải leak.
- Trục 2 (auth): HS256 pinned list literal (_ALLOWED_ALGOS), không đọc từ config → chặn alg-confusion. Missing sub/shop_id/role đều raise ValueError với message chứa tên claim (test match /shop_id/i). Bad sig → pyjwt.InvalidSignatureError propagate raw (không wrap) — test 3 assert đúng exception type. Identity @dataclass(frozen=True). Không có default fall-through.
- Trục 3 (side-effect): Alembic 0001 chỉ tạo 2 bảng + CREATE EXTENSION IF NOT EXISTS vector; downgrade đảo ngược đầy đủ. PgvectorRetriever.search SELECT-only. Không network call, không file I/O ngoài DB.
- Deferred (không blocker Phase 2, ghi lại cho Phase 3+/5):
  - verify_token chưa enforce exp/aud/iss — GĐ0 dev secret flow đủ, prod RS256+exp cần trước F3 auto-send.
  - Bảng shops/sellers/customers/conversations/pending_reply hoãn Phase 5 đúng scope §8.
  - Base.metadata.drop_all trong test_tenant_isolation nuke messages+embeddings của DB đích DATABASE_URL — dev shared DB được, CI provisions riêng.
- Verdict: match auto-verdict (APPROVE). concerns: [].
