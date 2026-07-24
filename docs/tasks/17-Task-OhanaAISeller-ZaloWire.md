# Spec 17 — GD0-ZALO Wire (turn Zalo scaffold into a real E2E channel)

> Bốn miếng chờ Zalo đã có: `channels/zalo/ZaloChannel` (parse_inbound placeholder), `api/webhook.py::build_router` (factory với `enabled=False`), `bridge/zalo_sender.MockZaloSender`, PII filter (spec 16 A0/B0/C0). Cái CHƯA có: xác thực chữ ký Zalo trên raw body, HTTP sender thật + refresh cycle 1h/3-tháng, envelope parser đúng shape Zalo, cột `zalo_oa_id` trên shops, và một dòng `include_router(webhook)` trong `app/main.py`. Spec này biến scaffold thành real Zalo — nhưng chốt cuối (mount) NẰM SAU cửa PDPL + PRE-004, không phải sau code.

**Origin:** discussion 2026-07-24 sau khi kiểm tra sẵn sàng Zalo (adp/16 chat) · **Owner (R):** Wyatt Ngo · **Approver (A):** Wyatt Ngo
**ROADMAP:** `GD0-ZALO` (§4, external, chờ Tân PRE-004 + PDPL owner)

## Context

**Trạng thái on-disk 2026-07-24** (đã kiểm bằng `git ls-files channels/ bridge/ api/webhook.py`):

- `channels/zalo/__init__.py` (44 dòng) — `ZaloChannel` class với `parse_inbound` payload shape `{customer_id, message}` **placeholder**, không phải Zalo envelope thật (`sender.id`, `event_name`, `message.msg_id`).
- `api/webhook.py:88` — comment `# TODO(PRE-004): verify platform signature over the RAW body BEFORE parsing.` `_ = req` giữ chỗ để verify pass raw body downstream.
- `bridge/zalo_sender.py` — `ZaloSender` Protocol (`send(shop_id, customer_id, text)`) + `MockZaloSender` (chỉ record vào `.sends`).
- `.env.example:26-28` — có `ZALO_OA_ACCESS_TOKEN=`, `ZALO_WEBHOOK_SECRET=` (rỗng). **KHÔNG có** `ZALO_APP_ID`, `ZALO_APP_SECRET_KEY`, và không có schema lưu token per-shop.
- `app/main.py:79-93` — `include_router(webhook_router)` **KHÔNG** xuất hiện. Đây là chốt chặn PDPL: không mount = zero traffic khách VN = đồng hồ 60 ngày chưa chạy.
- `db.WebhookEventLog` (migration `0009`) đã tồn tại với `(channel, platform_msg_id)` unique PK — spec 14 shipped, idempotency **đã sẵn** ở tầng DB nhưng CHƯA được call trong `api/webhook.py`.

**Ràng buộc bên ngoài (không code fix được):**

1. **Access token 1h + refresh token 3 tháng SINGLE-USE.** Zalo OAuth v4: mỗi lần refresh sinh cặp mới, refresh_token cũ chết ngay. Nếu 2 process cùng refresh → 1 thắng, 1 thua → mất luôn cả cặp → phải re-authorize manual (cần OA admin). → BẮT BUỘC `SELECT ... FOR UPDATE` (advisory lock hoặc row lock) quanh refresh.
2. **X-ZEvent-Signature formula CANONICAL (docs Zalo 2026-07-24):** `mac = sha256(appId + data + timeStamp + OAsecretKey)`, với `data` là chuỗi JSON body y hệt Zalo gửi (byte nguyên, không re-serialize). Key = **OA Secret Key, KHÔNG PHẢI App Secret Key** — bẫy 90% dev fail lần đầu. Hai key khác nhau: App Secret nằm trong `.env` (dùng OAuth), OA Secret Key cấp per-OA khi liên kết App↔OA — phải lưu per-shop cùng chỗ với access_token.
4. **Reactive window 48h (KHÔNG còn cap 8 tin từ 1/1/2026).** Docs Zalo `/v3.0/oa/quota/message` (screenshot 2026-07-24): "Từ ngày 1/1/2026, đối tác có thể gửi tin Tư vấn miễn phí KHÔNG GIỚI HẠN trong khung 48h. Sau ngày 1/3/2026 sẽ ngừng trả `cs_reply` field." Nghĩa là: `/message/cs` endpoint chỉ enforce window 48h reactive (last user message), KHÔNG còn cap 8 tin. Error `-224` giờ chỉ fire khi vượt window 48h. `promotion` message vẫn giới hạn `1/ngày`, `6/tháng` per user — nhưng spec 17 chỉ `cs`, không `promotion`. `GD0-WINDOW` item trong roadmap cần re-scope: chỉ warning window 48h, không đếm 8-msg.
5. **Zalo timeout webhook 2s → retry 30s/5m/15m/30m/1h.** Nếu draft engine + LLM đồng bộ >2s → phải ACK 200 trước, worker xử lý sau (item `GD0-INGEST` riêng — không thuộc spec này). Spec 17 giữ đường đồng bộ; nếu chạm 2s trên tin thật đầu tiên, `GD0-INGEST` mở gấp.
6. **Envelope shape user_send_text đã verify từ docs Zalo (screenshot Wyatt 2026-07-24).** Shape thật:
   ```json
   {
     "app_id":     "<string>",
     "sender":     {"id": "<string>"},
     "recipient":  {"id": "<string>"},
     "event_name": "user_send_text",
     "message":    {"text": "<string>", "msg_id": "<string>", "attachments": [...]?},
     "timestamp":  "<string unix-ms>"
   }
   ```
   **KHÔNG có `oa_id` ở top-level** — chỉ `app_id`. `oa_id` phải suy: với event `user_send_*`, `recipient.id` = oa_id (khách gửi TỚI OA); với event `oa_send_*` (echo), `sender.id` = oa_id. Đây là gọn hơn hầu hết mẫu code third-party (đa số giả định có `oa_id` top-level — SAI).
7. **Event `event_name` đầy đủ (từ docs):**
   - **User → OA (inbound):** `user_send_text`, `user_send_image`, `user_send_link`, `user_send_sticker`, `user_send_gif`, `user_send_audio`, `user_send_video`, `user_send_file`, `user_send_location`, `user_send_business_card`
   - **OA → User (echo, verified per docs):** `oa_send_text`, `oa_send_image`, `oa_send_file`, `oa_send_sticker`
   - **OA → User ẩn danh (từ nhóm/rating, per docs PDF):** `oa_send_anonymous_text`, `oa_send_anonymous_image`, `oa_send_anonymous_file`, `oa_send_anonymous_sticker` (có thêm field `user_id_by_app`, `message.conversation_id`)
   - **Read receipts / interaction:** `user_received_message`, `user_seen_message`, `user_click_chatnow`, `user_submit_info`
   - **Lifecycle:** `follow`, `unfollow`, `user_feedback`
   Spec 17 chỉ handle `user_send_text`; **tất cả event khác skip có log, KHÔNG raise** (crash = webhook 500 = retry storm 5 lần).
8. **API backup fetch có sẵn** — `GET /v2.0/oa/listrecentchat` (10 tin gần nhất OA↔user) và `GET /v2.0/oa/conversation?user_id=&offset=&count=` (tin trong 1 hội thoại, max 10). KHÔNG dùng trong spec 17 (webhook realtime là đường chính), nhưng ghi ở Out of scope làm backup nếu webhook drop.
9. **Quota check API có sẵn** — `POST /v3.0/oa/quota/message` (body `{user_id}`) trả `{last_interaction, cs_reply:{remain,total}, promotion:{daily_remain, daily_total, monthly_remain, monthly_total}}`. Có thể pre-flight check trước khi gửi để catch out-of-window / out-of-quota trước lúc call `/message/cs`. Spec 17 KHÔNG dùng (call trực tiếp, error `-224` fire khi vượt là đủ signal); item riêng nếu ops muốn proactive warning.

**Ranh giới có chủ đích:**

- Spec 17 KHÔNG mount webhook — mount là P4 và P4 BLOCKED. Code hoàn thành P0-P3 = 4 miếng ghép sẵn sàng, cần 1 dòng mount khi PRE-004 + PDPL owner sạch.
- Spec 17 KHÔNG làm 48h window scheduler (đó là `GD0-WINDOW`).
- Spec 17 KHÔNG làm ACK<2s + queue idempotency (đó là `GD0-INGEST`, keystone riêng). P3 integration test vẫn chạm `webhook_event_log` để không silent skip idempotency nhưng chỉ ở mức "call `record_event` với retry cùng key → 200 + không double".
- Spec 17 KHÔNG dựng LLMDrafter trong `main.py` — đó là spec 15 P3. P4 REFERENCE spec 15 P3 (không block).
- Spec 17 KHÔNG chạm `agent/policy_gate.py`, `agent/orchestrator.py`, `agent/drafter.py`. Đường ống downstream (`receive_and_draft` → PII → LLM → policy → PARK) đã có, không sửa.

## Pre-flight (verify on disk before authoring — audit-first)

- [ ] ROADMAP id `GD0-ZALO` tồn tại trong L1 — `grep -c "^| \`GD0-ZALO\`" docs/ROADMAP.md` → expected `1`
- [ ] `api/webhook.py:88` chứa comment TODO(PRE-004) — `grep -n "TODO(PRE-004)" api/webhook.py` → expected `1 dòng`
- [ ] `bridge/zalo_sender.py` chỉ có Mock — `grep -c "class.*Sender" bridge/zalo_sender.py` → expected `3` (Protocol + Mock + không có Http)
- [ ] Không có migration nào chạm `zalo_oa_tokens` — `ls db/migrations/versions/ | grep -c zalo` → expected `0`
- [ ] `app/main.py` chưa mount webhook — `grep -c "webhook" app/main.py` → expected `1 comment reference only`, không `include_router(webhook)`
- [ ] RISK_PATHS thi hành: `api/webhook.py`, `bridge/`, `db/migrations`, `agent/orchestrator.py`, `agent/policy_gate.py`, `tools/registry.py`, `auth/`, `api/inbox.py`, `api/admin.py`, `api/chat.py` — spec 17 chạm 4/10, đủ floor rule medium cho P0/P1/P2/P4.
- [ ] Wyatt ký RISK cho P0-P4 trước khi phase đầu tiên vào IN_PROGRESS

## Phases

### P0 — Config + token storage foundation

<!-- ADP:PHASE P0 -->
STATUS: DONE
EVIDENCE: commit=7474604, gate_exit=0, duration=15s, review=PASS(judge=APPROVE,model=unknown,bound=fd6dc882d059,tier=medium), smoke=N/A(P0 hàm data-layer thuần, không có mặt runtime người dùng quan sát; alembic upgrade/downgrade round-trip đo trong test là đủ.), ran=2026-07-24T21:29
ROADMAP: GD0-ZALO
GOAL: Có bảng `zalo_oa_tokens(shop_id PK, oa_id, access_token, refresh_token, access_expires_at, refresh_expires_at, oa_secret_key, updated_at)` + migration idempotent + repo có method `get_by_shop(shop_id)` và `update_tokens_locked(shop_id, ...)` với `SELECT ... FOR UPDATE`. Env vars `ZALO_APP_ID`, `ZALO_APP_SECRET_KEY` thêm vào `.env.example` (rỗng, nhóm dưới ZALO_ hiện có). Chưa có runtime user quan sát; đúng-sai chứng minh bằng test tất định trên repo + alembic upgrade/downgrade round-trip.
APPROACH: `oa_secret_key` để CÙNG bảng với token vì cả hai đều per-OA và cùng vòng đời (liên kết OA↔App), KHÔNG tách sang `shops` — tách = 2 truy vấn mỗi webhook + 2 nơi phải xoay khi rotate. `access_expires_at` là `TIMESTAMPTZ` không phải `expires_in` seconds vì thời điểm hết hạn không đổi khi row bị đọc lại — lưu `expires_in` phải cộng `now()` mỗi lần đọc, dễ off-by-race. `update_tokens_locked` dùng `SELECT ... FOR UPDATE` (Postgres row lock, không advisory lock) vì scope lock = 1 row = shop_id — advisory lock global làm serialize refresh giữa shops không cần thiết. Alternative đã bỏ: dùng `shops.zalo_*` cột — làm shops row hot (mọi request đọc), và migration retrofit đắt sau khi có data.
ALLOWED_FILES: db/migrations/versions/0010_zalo_oa_tokens.py, db/models.py, db/repos.py, .env.example, pyproject.toml, docs/codebase-map.md, tests/test_zalo_token_repo.py, docs/tasks/17-Task-OhanaAISeller-ZaloWire.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_zalo_token_repo.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache && .venv/bin/python .claude/hooks/guardrail.py $(find app agent retrieval parsing -name '*.py') && python3 scripts/ai_coder/gen_codebase_map.py --check && python3 scripts/roadmap_derive.py verify
RETRY: 0/3
RISK: medium (✅ WYATT KÝ 2026-07-24. Touches `db/migrations` ∈ RISK_PATHS — floor rule. Không high vì chỉ thêm bảng + repo thuần, không nối vào request path, không chạm money behavior.)
SMOKE: N/A P0 hàm data-layer thuần, không có mặt runtime người dùng quan sát; alembic upgrade/downgrade round-trip đo trong test là đủ.
REVIEW: PASS ref=docs/reviews/17-P0-auto-verdict.json
<!-- /ADP -->

1. Test (**RED first for medium+**): `test_zalo_token_repo.py` viết trước — assert `get_by_shop` trả None cho shop chưa tồn tại, `update_tokens_locked` snapshot values đúng, concurrent update giữ FOR UPDATE (dùng 2 async session cùng update 1 shop_id → thứ tự nghiêm ngặt).
2. Migration `0010_zalo_oa_tokens.py` — upgrade/downgrade phải round-trip sạch (pytest fixture đã có).
3. `db/models.py` add `ZaloOAToken` (đọc `Shop` để confirm naming convention: PascalCase, `__tablename__ = "zalo_oa_tokens"`, primary key `shop_id` với FK CASCADE tới `shops.id`).
4. `db/repos/zalo_token_repo.py` mới — 2 method.
5. `.env.example` thêm 2 dòng `ZALO_APP_ID=`, `ZALO_APP_SECRET_KEY=` (nhóm dưới `ZALO_OA_ACCESS_TOKEN`).
6. **STOP+WAIT** cho checkpoint.

### P1 — Signature verify at `api/webhook.py:88`

<!-- ADP:PHASE P1 -->
STATUS: IN_PROGRESS
ROADMAP: GD0-ZALO
GOAL: Payload không có header `X-ZEvent-Signature` HOẶC hash sai → HTTP 401 TRƯỚC khi `parse_inbound` chạy. Hash đúng (per `sha256_hex(app_id + raw_body_bytes.decode("utf-8") + timestamp + oa_secret_key)`, key = OA Secret Key per-shop từ `zalo_oa_tokens`, timestamp = `data["timestamp"]` string trong body) → pass, downstream nhận raw body đã verify. Verify chạy 1 lần trên raw bytes, downstream re-parse cùng bytes đó (không re-await `req.body()`). Test golden fixture: valid → 200, wrong sig → 401, missing header → 401, malformed JSON body → 400, replay attack (timestamp cũ >5min) → 401, oa_id không nhận diện được → 401.
APPROACH: Verify TRƯỚC parse là chốt chặn — nếu parse trước rồi verify, `pydantic` đã có thể throw hoặc leak side-effect. `hmac.compare_digest` (constant-time) chống timing attack. Timestamp check ±5min chống replay — cửa sổ hẹp vì Zalo push realtime, không cần lỏng. **Key lookup: `oa_id` KHÔNG có ở top-level webhook** (chỉ `app_id` — bẫy #2, gọn hơn mẫu code third-party). Suy `oa_id` từ candidate `{sender.id, recipient.id}`: với `user_send_*` event, `recipient.id` là oa_id; với `oa_send_*` echo, `sender.id` là oa_id. Verify lookup thử cả 2 IDs vào `zalo_oa_tokens.oa_id` — 1 match → dùng `oa_secret_key` từ row đó; 0 match → 401 (không nhận diện). Index `idx_zalo_oa_tokens_oa_id` tra nhanh. `oa_id` KHÔNG PHẢI shop_id — 1 shop có thể có nhiều OA (multi-brand), 1 OA thuộc đúng 1 shop. Alternative đã bỏ: giả định `body["oa_id"]` — SAI, envelope Zalo không có field này (đã xác từ docs 2026-07-24). Alternative đã bỏ: verify sau parse — nếu parse throw, ta không biết đã verify hay chưa, tạo confusion khi debug. Alternative đã bỏ: dùng App Secret Key thay OA Secret Key — sai key = 100% verify fail dù hash đúng, đây là bẫy #1.
ALLOWED_FILES: api/webhook.py, channels/zalo/signature.py, channels/zalo/__init__.py, db/repos.py, docs/codebase-map.md, tests/test_zalo_signature.py, tests/test_webhook_signature.py, tests/test_channel_abstraction.py, tests/test_message_history.py, docs/tasks/17-Task-OhanaAISeller-ZaloWire.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_zalo_signature.py tests/test_webhook_signature.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache && .venv/bin/python .claude/hooks/guardrail.py $(find app agent retrieval parsing -name '*.py') && python3 scripts/ai_coder/gen_codebase_map.py --check && python3 scripts/roadmap_derive.py verify
RETRY: 0/3
RISK: high (✅ WYATT KÝ 2026-07-24. Security control tại boundary — verify sót = attacker inject tin khách giả mạo vào draft engine, tin lỗi rời máy khi P4 mount. Floor: `api/webhook.py` ∈ RISK_PATHS.)
BLOCKED_BY: P0 DONE (cần bảng `zalo_oa_tokens` + `oa_secret_key` column để lookup key theo `oa_id`)
SMOKE: N/A P1 signature verify là hàm thuần + endpoint test; không có runtime mount (P4 blocked); test tất định trên golden fixture đủ chứng minh. Runtime observation phải chờ P4 mount + Zalo push thật.
REVIEW: PASS ref=docs/reviews/17-P1-auto-verdict.json human=docs/reviews/17-P1-human-review.md
<!-- /ADP -->

1. Test (**RED first — RISK:high yêu cầu TDD chặt**): viết `tests/test_zalo_signature.py` — 7 case tất định (valid với oa_id match qua recipient.id, valid với oa_id match qua sender.id [echo], wrong-sig, missing-header, malformed-body, replay-old-timestamp, tampered-body-same-timestamp, oa_id không có trong DB). Confirm ĐỎ.
2. Test `tests/test_webhook_signature.py` — 4 case qua `TestClient`: valid → 200, wrong sig → 401, missing header → 401, replay → 401. Confirm ĐỎ.
3. `channels/zalo/signature.py` mới — export `async def verify_zalo_signature(req: Request, oa_secret_lookup: Callable[[str], Awaitable[str | None]]) -> bytes` trả raw body sau khi verify. `oa_secret_lookup` được gọi 2 lần (thử `sender.id` rồi `recipient.id`) — mỗi lần cache-friendly single-row query.
4. Migration `0011_zalo_oa_tokens_oa_id_index.py` — thêm `CREATE INDEX idx_zalo_oa_tokens_oa_id ON zalo_oa_tokens(oa_id)`.
5. `db/repos/zalo_token_repo.py` add `async def get_oa_secret_by_oa_id(oa_id: str) -> str | None`.
6. Sửa `api/webhook.py`: TRƯỚC dòng `msg = adapter.parse_inbound(payload)`, chèn `raw_body = await verify_zalo_signature(req, get_oa_secret_by_oa_id)`, và reparse `payload = json.loads(raw_body)` để đảm bảo cùng bytes.
7. Confirm test XANH sau impl.
8. **STOP+WAIT** cho checkpoint. **Sync review với Wyatt trước checkpoint** (RISK:high).

### P2 — Real ZaloSender HTTP + refresh cron

<!-- ADP:PHASE P2 -->
STATUS: TODO
ROADMAP: GD0-ZALO
GOAL: `bridge.zalo_sender.HttpZaloSender` (mới) implement `ZaloSender` Protocol, gửi `POST https://openapi.zalo.me/v3.0/oa/message/cs` với header `access_token: <token>` (KHÔNG PHẢI Authorization Bearer), body `{"recipient": {"user_id"}, "message": {"text"}}`, parse response `{"error": int, "message": str, "data": {...}}`. Error `-32` (token expired) → refresh + retry 1 lần; error `-201` (invalid recipient) hoặc `-224` (out of window 48h — sau 1/1/2026 KHÔNG có cap 8 msg nữa) hoặc `-114` (rate limit) → raise `SendPolicyError` phân loại. `bridge.zalo_token_refresh.refresh_shop_tokens(shop_id)` (mới) — POST `https://oauth.zaloapp.com/v4/oa/access_token` với `secret_key: <app_secret>` header + body `app_id=<>&grant_type=refresh_token&refresh_token=<>`, dùng `SELECT ... FOR UPDATE` từ P0 repo, ghi cặp mới (refresh_token cũ CHẾT sau call). Test dùng `respx` mock HTTP, không hit Zalo thật; MockZaloSender GIỮ NGUYÊN cho tests hiện tại. Live smoke chạy khi PRE-004 giao credentials sandbox.
APPROACH: Retry -32 ĐÚNG 1 lần vì refresh đã single-use — retry vô hạn = burn hết refresh_token. Concurrent refresh chống bằng FOR UPDATE ở P0 repo: process 2 chờ process 1 xong, đọc token mới ngay, không cần refresh nữa (check `access_expires_at > now()` sau khi lock — pattern double-check locking). `SendPolicyError` phân loại chứ không single exception vì downstream (orchestrator/policy_gate tương lai) có action khác nhau: invalid_recipient → mark customer as unreachable, out_of_window → escalate to seller manual, rate_limited → backoff enqueue. Timeout 5s cho HTTP call (Zalo p95 ~1s theo doc) — vượt = Zalo có sự cố, không phải bug ta. Alternative đã bỏ: gộp `HttpZaloSender` + refresh vào 1 class — vi phạm SRP, và refresh chạy được từ cron scheduler độc lập với send path. Alternative đã bỏ: dùng `httpx.AsyncClient` mới mỗi call — thiếu connection pooling, dựng qua `bridge.__init__` shared client với `limits=httpx.Limits(max_connections=100)`.
ALLOWED_FILES: bridge/zalo_sender.py, bridge/zalo_token_refresh.py, bridge/__init__.py, tests/test_http_zalo_sender.py, tests/test_zalo_token_refresh.py, docs/tasks/17-Task-OhanaAISeller-ZaloWire.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_http_zalo_sender.py tests/test_zalo_token_refresh.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache && .venv/bin/python .claude/hooks/guardrail.py $(find app agent retrieval parsing -name '*.py') && python3 scripts/ai_coder/gen_codebase_map.py --check && python3 scripts/roadmap_derive.py verify
RETRY: 0/3
RISK: high (✅ WYATT KÝ 2026-07-24. Real money-adjacent — tin OA rời máy tới khách thật khi mount, sai sender = spam khách hoặc leak token. Floor: `bridge/` ∈ RISK_PATHS.)
BLOCKED_BY: P0 DONE (cần repo + bảng tokens); P1 DONE (verify là ranh giới trust, sender chỉ chạy trên request đã verify).
SMOKE: N/A P2 sender + refresh chạy được unit-test đầy đủ với `respx` mock. Live smoke với sandbox Zalo là item RIÊNG (cần PRE-004 giao creds test) — smoke thật sẽ chạy khi P4 mount và có tin sandbox đi qua toàn tuyến. Ghi PASS ref khi có; giờ N/A giữ honest.
<!-- /ADP -->

1. Test (**RED first — RISK:high**): `tests/test_http_zalo_sender.py` — 6 case (success, -32 refresh + retry success, -32 refresh fail, -201/-224/-114 raise SendPolicyError, timeout raise HTTPError, wrong response shape). Dùng `respx` mock `openapi.zalo.me`. Confirm ĐỎ.
2. Test `tests/test_zalo_token_refresh.py` — 5 case (fresh success, concurrent double-check hit, refresh fail 401 raise, malformed response raise, response ghi đúng row với FOR UPDATE serialize). Confirm ĐỎ.
3. `bridge/__init__.py` add shared `httpx.AsyncClient` với timeout+limits.
4. `bridge/zalo_sender.py` add `HttpZaloSender` class + `SendPolicyError(Exception)` với `.category` field.
5. `bridge/zalo_token_refresh.py` mới — `async def refresh_shop_tokens(shop_id: str, session_factory) -> None`.
6. Confirm test XANH sau impl.
7. **STOP+WAIT** cho checkpoint. **Sync review với Wyatt trước checkpoint** (RISK:high).

### P3 — Real Zalo envelope parser + integration test

<!-- ADP:PHASE P3 -->
STATUS: TODO
ROADMAP: GD0-ZALO
GOAL: `channels/zalo/__init__.py::ZaloChannel.parse_inbound` chấp nhận Zalo envelope THẬT `{app_id, sender:{id}, recipient:{id}, event_name, message:{text, msg_id, attachments?}, timestamp}` (không phải placeholder `{customer_id, message}` hiện tại; **KHÔNG có `oa_id` top-level** — chỉ `app_id`) — chỉ event `user_send_text` (event khác skip có log INFO, không raise). `sender.id` = customer external_user_id; `recipient.id` = oa_id (dùng để lookup shop_id qua `endpoint_to_shop` map ở P4). Integration test end-to-end: valid signed payload → verify (P1) → parse (P3) → resolve_conversation → MessageRepo.append → receive_and_draft (dùng MockDrafter + MockZaloSender) → PendingReply row PARK. Test 2 tin cùng `msg_id` → chỉ 1 `messages` row + 1 `pending_replies` row (idempotency qua `webhook_event_log`).
APPROACH: Không dùng Pydantic model — dùng `TypedDict` (channels/zalo/envelope.py) + `dict.get()` với validation thủ công. Pydantic validate chặt sẽ raise 400 trên field lạ (Zalo có thể thêm field bất cứ lúc nào — vd `attachments` array cho photo/gif/file event), TypedDict + `get()` mềm hơn. Event skip list đầy đủ theo docs (2026-07-24): `user_send_image`, `user_send_link`, `user_send_sticker`, `user_send_gif`, `user_send_audio`, `user_send_video`, `user_send_file`, `user_send_location`, `user_send_business_card`, `oa_send_*` echo — tất cả return `None` có log INFO. Spec 17 chỉ text; ảnh/sticker/media land ở spec khác. `event_name` unknown (Zalo thêm mới sau) cũng return `None` — crash = webhook 500 = Zalo retry storm 5 lần. Alternative đã bỏ: giả định `body["oa_id"]` (SAI, không có field). Alternative đã bỏ: crash trên unknown event (retry storm risk). Alternative đã bỏ: chạy integration test với LLMDrafter thật — làm test flaky và cần Together key, mà spec 15 P3 mới wire LLMDrafter — dùng MockDrafter đúng scope.
ALLOWED_FILES: channels/zalo/__init__.py, channels/zalo/envelope.py, tests/test_zalo_parser.py, tests/test_webhook_e2e.py, docs/tasks/17-Task-OhanaAISeller-ZaloWire.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_zalo_parser.py tests/test_webhook_e2e.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache && .venv/bin/python .claude/hooks/guardrail.py $(find app agent retrieval parsing -name '*.py') && python3 scripts/ai_coder/gen_codebase_map.py --check && python3 scripts/roadmap_derive.py verify
RETRY: 0/3
RISK: medium (✅ WYATT KÝ 2026-07-24. Envelope shape wrong = tin khách drop silent = mất chuyện mãi mãi. `channels/zalo/` KHÔNG trong RISK_PATHS trực tiếp nhưng integration test chạm `api/webhook.py` ∈ RISK_PATHS. Không high vì downstream tất cả đã có test riêng — P3 chỉ thay parse_inbound + wire.)
BLOCKED_BY: P0 DONE, P1 DONE (verify + tokens phải sẵn để integration test qua verify path).
SMOKE: N/A P3 integration test đo E2E trong test env đầy đủ (fake webhook → PendingReply row). Sandbox live smoke qua Zalo test OA sẽ chạy khi PRE-004 giao credentials + P4 mount — spec 17 giữ N/A vì runtime chưa observe được.
<!-- /ADP -->

1. Test (RED first — MEDIUM cần RED cho gate test): `tests/test_zalo_parser.py` — 7 case (valid user_send_text với minimal fields, valid user_send_text với `attachments` field lạ [ignore không crash], missing sender.id → ValueError, missing message.text → ValueError, unknown event_name → return None có log INFO, user_send_image [known non-text] → return None có log INFO, malformed timestamp → ValueError). Confirm ĐỎ.
2. Test `tests/test_webhook_e2e.py` — 3 case (E2E park success, duplicate msg_id → 1 row via idempotency, verify fail → 401 không parse). Confirm ĐỎ.
3. `channels/zalo/envelope.py` mới — `TypedDict` cho `ZaloWebhookPayload`, `ZaloMessage`, `ZaloSender`, `ZaloRecipient` (KHÔNG có `oa_id` top-level).
4. Sửa `channels/zalo/__init__.py::parse_inbound` — accept envelope thật, event filter danh sách 10 skip event, return `InboundMessage` hoặc `None`.
5. Sửa `api/webhook.py`: handle `None` từ parse (skip event, ACK 200 nhưng không xử lý).
6. Confirm test XANH.
7. **STOP+WAIT** cho checkpoint.

### P4 — Mount webhook + `endpoint_to_shop` loader (BLOCKED)

<!-- ADP:PHASE P4 -->
STATUS: BLOCKED
ROADMAP: GD0-ZALO
GOAL: `app/main.py` mount `build_webhook_router(...)` với `enabled=False` mặc định (env `OHANA_WEBHOOK_ENABLED` bật). `shops` table thêm cột `zalo_oa_id` (nullable, unique) + `zalo_endpoint_key` (nullable, unique). `endpoint_to_shop: dict[tuple[str, str], str]` load 1 lần ở app startup từ DB. Health check `/health` báo `webhook_enabled: bool` + `zalo_shops_configured: int` để oncall thấy trước khi khách gửi tin đầu tiên. Khi `enabled=True` + tin sandbox đầu tiên đi qua = **đồng hồ PDPL 60 ngày CHẠY** (TIA + consent notification bắt buộc trong 60 ngày). BLOCK cho tới khi có PRE-004 (Tân creds) + PRE-PDPL-OWNER (chủ pháp lý ký).
APPROACH: `enabled=False` mặc định là chốt chặn KHÔNG thay được bằng lời dặn — code path exists nhưng return 503 tới khi env bật. Env chứ không code hardcode: env sai gây 503 (fail-loud), hardcode = phải redeploy để bật/tắt trong sự cố. `endpoint_to_shop` load 1 lần startup rồi cache — không tra DB mỗi webhook (cùng lý do `_client_cache` ở `api/chat.py`). Cột `zalo_endpoint_key` unique tách khỏi `zalo_oa_id` vì `oa_id` có thể trùng nếu 1 OA phục vụ nhiều shop (test env), `endpoint_key` = path segment trong `/webhook/zalo/{endpoint_key}` phải unique. Health check thể hiện config trạng thái vì "webhook mounted nhưng enabled=false" và "webhook enabled + zalo_shops_configured=0" là hai lỗi cấu hình khác nhau, phải phân biệt. Alternative đã bỏ: enabled=True mặc định — 1 sai env deploy = PDPL clock chạy oan. Alternative đã bỏ: lookup endpoint_to_shop mỗi request từ DB — 1 query thêm trên hot path webhook (Zalo timeout 2s là ngân sách chặt).
ALLOWED_FILES: app/main.py, db/migrations/versions/0012_shops_zalo_endpoint.py, db/models.py, db/shop_repo.py, api/health.py, tests/test_app_boot.py, tests/test_health.py, docs/tasks/17-Task-OhanaAISeller-ZaloWire.md, docs/smokes/, docs/reviews/
GATE: .venv/bin/python -m pytest tests/test_app_boot.py tests/test_health.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache && .venv/bin/python .claude/hooks/guardrail.py $(find app agent retrieval parsing -name '*.py') && python3 scripts/ai_coder/gen_codebase_map.py --check && python3 scripts/roadmap_derive.py verify
RETRY: 0/3
RISK: high (✅ WYATT KÝ 2026-07-24 pending PRE-004 + PRE-PDPL-OWNER unblock. Mount = kích hoạt PDPL 60-day clock khi tin khách VN thật đầu tiên đi qua. Sai config = tin lỗi rời máy khi enabled=True. Floor: `db/migrations` ∈ RISK_PATHS + `app/main.py` thay đổi request routing app-wide. Khi unblock: re-review RISK trước khi flip STATUS: BLOCKED → TODO.)
BLOCKED_BY: **PRE-004** — Tân giao Zalo OA credentials (test OA + prod OA) + doc envelope thật để lock schema. **PRE-PDPL-OWNER** — chủ pháp lý ký TIA (Transfer Impact Assessment) + consent notification pipeline sẵn sàng chạy trong 60 ngày. **REF (không block):** spec 15 P3 (LLMDrafter dựng trong `main.py`) — nếu spec 15 P3 chưa land khi P4 unblock, dùng MockDrafter tạm; sai giọng shop nhưng đúng an toàn.
SMOKE: N/A phase BLOCKED, chưa có runtime để smoke. Khi unblock: sandbox Zalo OA → gửi tin thật đi qua chuỗi verify→parse→park; smoke live sẽ dán vào `docs/smokes/17-P4.md` với OBSERVED = curl thật + row PendingReply thật.
<!-- /ADP -->

1. **KHÔNG bắt đầu P4** cho tới khi BLOCKED_BY resolve — kiểm bằng `test_zalo_creds_present.py` (chạy trong CI, skip nếu env rỗng) + PDPL owner ký `docs/decisions/DEC-OHANA-XX-pdpl-owner.md` (ACCEPTED, không PROPOSED).
2. Khi unblock, chuyển STATUS: BLOCKED → TODO, xin Wyatt ký RISK lần nữa (BLOCKED sang code active = re-review), rồi bắt đầu TDD RED first.

## Out of scope

- **`GD0-INGEST` (webhook ACK<2s + queue + double-check idempotency)** — Keystone #1 riêng, sẽ mở nếu P3/P4 smoke chạm 2s. Spec 17 giữ đồng bộ, chấp nhận rủi ro nếu Zalo timeout retry (Zalo retry 5 lần, mất tin cực hiếm khi latency <2s).
- **`GD0-WINDOW` (48h reactive window scheduler + seller warning)** — chính sách Zalo, không thuộc integration.
- **Spec 15 P3 (LLMDrafter dựng trong `main.py`)** — REF từ P4, không block. Có thể dùng MockDrafter khi PRE-004 unblock nhưng LLMDrafter chưa land.
- **Auto-send tới khách** — mọi draft PARK ở GĐ0 (workflow §5 + policy_gate). Auto-send là `GD1` sau khi eval harness + intent classifier vào chỗ.
- **Zalo template message (transaction/promotion endpoints)** — spec 17 chỉ `/message/cs` (customer-service). Template message land khi có use case (order update, promo notification).
- **Multi-brand per shop (1 shop nhiều OA)** — schema hỗ trợ (`zalo_oa_id` per token row, không per shop row) nhưng loader P4 chỉ 1 OA/shop. Multi-brand khi có seller yêu cầu.
- **Refresh cron scheduling** — P2 export function `refresh_shop_tokens(shop_id)`; scheduler thực (APScheduler? Celery beat?) là quyết định riêng — spec 17 giữ function callable, scheduler infra là `GD0-CRON` riêng.
- **API backup fetch (`/v2.0/oa/listrecentchat`, `/v2.0/oa/conversation`)** — Zalo cung cấp 2 endpoint đọc tin nhắn (10 tin gần nhất OA↔user, tin trong 1 hội thoại). Có thể dùng làm backup nếu webhook drop (Zalo retry 5 lần rồi bỏ). Không thuộc spec 17 vì webhook realtime là đường chính GĐ0. Nếu ops thấy tin drop trên logs, mở spec riêng `GD0-BACKFILL`.
- **Quota pre-flight check (`POST /v3.0/oa/quota/message`)** — Zalo cho check quota per-user trước khi gửi (last_interaction, cs_reply remain, promotion daily/monthly remain). Spec 17 KHÔNG dùng — call trực tiếp và handle error `-224`/`-114` là đủ. Item riêng nếu ops muốn proactive warning cho seller.
- **Anonymous OA send events (`oa_send_anonymous_text/image/file/sticker`)** — dành cho tin nhắn từ nhóm/rating (user chưa follow OA), có thêm field `user_id_by_app` + `message.conversation_id`. P3 skip có log; nếu sau này cần route (unlikely GĐ0), mở spec riêng.
