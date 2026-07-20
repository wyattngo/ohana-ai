# 11-Task-OhanaAISeller-ShopsPersona

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-20 "tạo GD0-SHOPS") -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng trục safety→trust→stability→growth, -->
<!-- KHÔNG dùng Survival Framework LR/WP/TV/UR — Ohana không có cột tài chính. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | `shops` + `shop_profile` — persona vào prompt, knowledge vào lookup tất định |
| Parent | `GD0-SHOPS` (L1 `docs/ROADMAP.md` §4.1) |
| Depends-on | Spec 06 (Foundation, DONE) · Spec 10 (History, DONE — lấy `0006`) |
| **Supersedes** | **`docs/tasks/03-Task-GD0-AcceptanceBackfill.md` Phase 1** — xem §1.2 |
| Unblocks | `Drafter` implementation (chưa có chủ — xem §1.3) · `GD0-EVAL` (persona là ground truth) |
| Owner | R: Claude · A: Wyatt |
| Branch | `main` (commit thẳng — khớp spec 06–10) |
| Spec type | Feature · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

### 1.1 `shop_id` hiện là một chuỗi không có chủ

`auth/identity.py` đọc `shop_id` từ JWT claim đã verify và fail-closed nếu thiếu — phần đó đúng. Nhưng **không có bảng nào định nghĩa shop nào tồn tại**. `db/models.py` có 6 model (`Message`, `Embedding`, `Customer`, `Conversation`, `OrderDraft`, `PendingReply`); `shops` **không có**. `shop_id` là `Text` trần ở mọi bảng, không FK về đâu cả.

Nguồn `shop_id` duy nhất hôm nay là `api/mock_auth.py` — **dev-only**, mint JWT với `_FIXTURE_SHOP_ID` hardcode. Nghĩa là toàn bộ tenant boundary của hệ thống đang tựa vào một hằng số fixture.

Hệ quả cụ thể: một JWT hợp lệ có thể mang `shop_id` **bất kỳ chuỗi nào** và mọi tầng dưới sẽ tin. Composite FK của spec 06/10 chặn được row shop A trỏ row shop B, nhưng KHÔNG chặn được một `shop_id` chưa từng tồn tại — vì không có bảng cha để tham chiếu.

### 1.2 Va chạm: `GD0-SHOPS` đã có nhà, và nhà đó hết hạn blocker

`docs/tasks/03-Task-GD0-AcceptanceBackfill.md` Phase 1 mang `ROADMAP: GD0-SHOPS`, `STATUS: TODO`; L3 map `GD0-SHOPS → 03:1`. Nó bao: bảng `shops`, onboard flow, JWT từ DB thật, test cross-shop.

Hai vấn đề với việc để nguyên nó:

1. **`BLOCKED_BY: PRE-007 (hosting region ADR phải ACCEPTED trước)` — PRE-007 đã ACCEPTED 2026-07-19.** Blocker hết hạn hơn một ngày mà không ai gỡ. Đây là lần thứ HAI trong cùng một phiên gặp cùng một hình dạng lỗi: mypy `api/`/`auth/` bị loại vì "10 lỗi Depends" đã được vá từ lâu. **Một điều kiện chặn sống lâu hơn lý do của nó thì không còn là điều kiện chặn — nó là quán tính.**
2. **Nó viết TRƯỚC D7/D10 (2026-07-20)** nên không có `shop_profile`, không có `lookup_size`/`lookup_shipping`, không có cap persona. Acceptance `GD0-SHOPS` trong L1 giờ đòi đủ cả.

⇒ Wyatt chốt (2026-07-20): **spec 11 bao trọn, `03:1` → SUPERSEDED**. Không xoá phase đó — đánh dấu và trỏ sang đây.

### 1.3 ⚠️ Phát hiện: persona sẽ chưa có ai tiêu thụ

`shop_profile.persona` được thiết kế để **ráp vào system prompt của AI Seller** (D7 tầng 3). Nhưng AI Seller **chưa tồn tại**: `agent/orchestrator.Drafter` là Protocol, **zero implementation** trong toàn repo (xác nhận `grep -rn "class .*Drafter.*Protocol"` = 1 hit duy nhất, chính là khai báo).

Và **không work item nào trong L1 §4 sở hữu việc xây `Drafter`** — `GD0-POLICY` bao `policy_gate` + orchestrator + `PendingReply`, không bao phần sinh draft. Đây là mảnh khuyết thật giữa "có persona" và "AI Seller nói bằng giọng shop".

⇒ Spec này **KHÔNG xây `Drafter`** (scope sẽ nổ). Nó giao `build_persona_prompt(profile) -> str` — hàm thuần, cap cứng, test được — rồi dừng. **Cần một work item L1 mới cho `Drafter`**; ghi ở §12 để không trôi.

### Audit on-disk 2026-07-20 — HEAD `11994ec`, đo bằng lệnh thật

1. ✅ `shops` / `shop_profile` không tồn tại — `db/models.py`, `db/migrations/versions/`.
2. ✅ Migration mới nhất `0006_message_conversation_fk` ⇒ spec 11 lấy **`0007`**; spec 03 dịch lần **thứ TƯ** → `0008`/`0009`/`0010`. Xem PRE-1103.
3. ✅ `api/mock_auth.py:63` mint JWT với `_FIXTURE_SHOP_ID` hardcode, gate `_is_dev_env()`.
4. ✅ `api/admin.py:134` `build_router(embedder, session_factory, admin_dep)` — hiện chỉ 1 route `POST /admin/wiki/ingest`.
5. ✅ `tools/registry.ToolHandler = Callable[[str, str, dict], Awaitable[dict]]` — handler nhận `(user_id, shop_id, args)`, và `shop_id` **không được** xuất hiện trong `parameters`, nên LLM không chĩa tool sang shop khác được. Đây đúng là seam cho 2 hàm lookup.
6. ✅ `db/repos.py` — 3 repo, đều `__init__(session, *, shop_scope)`.
7. ✅ mypy scope giờ gồm `api/` + `auth/` (49 file, 2026-07-20) ⇒ GATE_FULL phải dùng scope mới.
8. ⚠️ `agent/orchestrator.Drafter` zero implementation — §1.3.

---

## §2 — Goal

**VI:** Mỗi `shop_id` chạy trong hệ thống là một row `shops` có thật, phát ra từ onboard đã xác thực, không phải chuỗi tự khai. Kiến thức shop tách theo HÌNH DẠNG: văn xuôi → persona ráp prompt có cap cứng; fact có cấu trúc → JSONB + hai hàm tra cứu tất định trả `not_found` tường minh. Chứng minh bằng `lookup_size(160,50)=="M"` và bằng test cross-shop, không bằng LLM-as-judge.

**EN:** Every `shop_id` in play is a real `shops` row minted by an authenticated onboard, not a self-asserted string. Shop knowledge is split by data SHAPE: prose becomes a hard-capped persona prompt fragment; structured facts live in JSONB behind two deterministic lookups that return an explicit `not_found`. Proven by `lookup_size(160,50)=="M"` and cross-shop tests — never by an LLM judge.

---

## §3 — Scope

- `db/models.py` — `Shop` + `ShopProfile` (composite FK `(shop_id, id)` pattern như spec 06).
- `db/migrations/versions/0007_shops_profile.py`.
- `db/repos.py` — `ShopProfileRepo(session, *, shop_scope)`.
- `parsing/` hoặc `agent/` — Pydantic model cho `knowledge` JSONB (validate lúc **GHI**).
- `tools/shop_kb.py` (mới) — `lookup_size`, `lookup_shipping` + `build_tool`.
- `agent/persona.py` (mới) — `build_persona_prompt(profile) -> str`, cap cứng.
- `api/admin.py` — `POST /admin/shops` (onboard) + `PUT /admin/shops/{id}/profile`.
- `auth/identity.py` — mint JWT từ shop THẬT (thay stub).
- `tests/test_shops_persona.py` (mới).

### Out of scope (cố ý)

- ❌ **`Drafter` implementation** — §1.3. Persona chưa có ai tiêu thụ sau spec này; đó là finding, không phải thiếu sót của spec.
- ❌ **UI sửa profile** — `web/` không đụng. Onboard + profile qua API admin trước.
- ❌ **Per-shop RAG** — D8/D9: kiến thức shop KHÔNG đi vector store ở GĐ0.
- ❌ **Gỡ `api/mock_auth.py`** — vẫn cần cho dev; chỉ thôi làm nguồn `shop_id` DUY NHẤT.
- ❌ **Đo lại cap token** — ISSUE-022/023 giữ nguyên, spec này chỉ *thi hành* cap đã ký.

---

## §4 — Safety Gate Check (trục Ohana: safety → trust → stability → growth)

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Đây là spec đầu tiên khiến `shop_id` có **bảng cha**. Composite FK từ `shop_profile` → `shops(id)` + repo `shop_scope` giữ scope ở tầng SQL. Rủi ro lớn nhất KHÔNG phải schema mà là **cache**: `shop_profile` sẽ được đọc mỗi lượt, ai đó sẽ cache nó, và cache sai key = cross-tenant leak không đi qua SQL nên FK không cứu được. ⇒ Nếu thêm cache, key PHẢI là `shop_id` và PHẢI có test 2 shop song song. | PASS (kèm điều kiện cache) |
| **User trust** | AI Seller nói bằng giọng shop và **không bao giờ lộ là Ohana/là AI** (§2.1 cam kết lõi). Persona là nơi cam kết đó sống hoặc chết. | PASS |
| **Stability** | Bảng mới, không backfill (chưa có shop nào). Migration reversible thật (drop bảng). | PASS |
| **Growth** | Mở khoá onboard shop thật — điều kiện cần của mọi thứ sau GĐ0. | PASS |

**RED FLAG scan:**

- [x] **`knowledge` JSONB phải validate lúc GHI, không phải lúc ĐỌC.** Không có Pydantic ở đường ghi thì `lookup_size` nổ trên data lệch shape — và nổ ở production, trên dữ liệu của một shop thật, giữa cuộc trò chuyện với khách. Validate lúc đọc là hoãn lỗi tới lúc đắt nhất.
- [x] **`lookup_*` phải trả `not_found` TƯỜNG MINH, không trả rỗng/None mơ hồ.** Đây không phải chi tiết API — nó CHÍNH LÀ tín hiệu confidence-gated escalation (D9). RAG không bao giờ nói "không biết"; hàm tất định thì có, và đó là lý do D9 cấm size chart đi RAG.
- [x] **Cap persona ở tầng CỘT.** ISSUE-022 (persona 2000) + ISSUE-023 (history 4000) **chia CHUNG một ngân sách prompt**: 2000 + 4000 = 6000 ký tự ≈ 1800 token, chưa kể system prompt + tool schema. Cả hai số đều CHƯA đo tokenizer thật. Spec này thi hành cap, không hợp thức hoá con số.
- [x] **Test identity-leak trên phần TẤT ĐỊNH.** `build_persona_prompt` không bao giờ được nhả chuỗi "Ohana" vào prompt của AI Seller. ⚠️ Đây KHÔNG phải bằng chứng AI không lộ danh tính lúc chạy — cái đó cần `Drafter` + LLM thật + eval. Đừng đọc test này rộng hơn nó chứng minh.
- [ ] ⚠️ **Onboard endpoint tạo tenant mới** — `POST /admin/shops` là đường sinh ra tenant. `require_admin` là gate duy nhất. Nếu admin token rò, kẻ tấn công tạo shop tuỳ ý. Chấp nhận được ở GĐ0 (admin = Wyatt/Sơn), nhưng phải ghi ra.

---

## §5 — Source files

Đọc TRƯỚC khi sửa: `db/models.py` (§Customer/§Conversation cho pattern composite FK) · `db/repos.py` (pattern `shop_scope`) · `db/migrations/versions/0006_message_conversation_fk.py` (style migration) · `auth/identity.py` · `api/mock_auth.py` (hiểu stub đang thay) · `api/admin.py` · `tools/registry.py` (shape `Tool`, `ToolHandler`) · `tools/wiki.py` (mẫu `build_tool`) · `agent/orchestrator.py` (cap history — để cap persona nhất quán).

---

## §6 — PRE checks

```
PRE-1101: Schema `shop_profile` — MỘT cột persona hay BẢY cột rời? Wyatt chốt.
  Trạng thái: ✅ WYATT KÝ 2026-07-20 — **MỘT cột `persona_md TEXT`, cap 2000 ký tự.**
              D10 (7 cột rời) bị thay thế. Cap ở tầng CỘT ⇒ ngân sách token kiểm
              soát được ở đúng một chỗ. Đổi lại: UI/seller làm việc với markdown thô.
  Nguồn mâu thuẫn đã giải (giữ lại để không ai "khôi phục" D10):
    (a) D10 (brief-10, ký 2026-07-20): 7 cột text rời — display_name · industry ·
        tone_notes · policy_return · policy_cod · policy_shipping_note · greeting.
    (b) L1 acceptance GD0-SHOPS (cùng ngày, sau review): "cap ở tầng CỘT, không cap
        từng field rời" ⇒ MỘT cột `persona_md TEXT` ≤ 2000 ký tự.
  Trade-off thật:
    - 7 cột rời: UI bind được từng field, seller điền form thay vì viết markdown.
      Nhưng cap TỔNG không kiểm soát được — cap từng field thì tổng vẫn trôi, mà
      cả 7 field đằng nào cũng nối vào CÙNG một prompt. Và thêm/bớt field sau khi
      UI đã bind = breaking change.
    - 1 blob `persona_md`: cap cứng ở tầng cột, giải luôn bài toán ngân sách token.
      Đổi lại seller (hoặc UI) phải làm việc với markdown thô.
  KHÔNG tự quyết. Số cột quyết định cả migration lẫn hình dạng API.

PRE-1102: `profile_status(draft|approved)` + `approved_by` — ai duyệt? Wyatt chốt.
  Trạng thái: ✅ WYATT KÝ 2026-07-20 — **`published_at TIMESTAMPTZ NULL`**, KHÔNG
              `profile_status`/`approved_by`/`approved_at`. `NULL` = chưa phát hành.
              Lý do: không có người duyệt thứ hai nào tồn tại ⇒ cột tên "approved"
              sẽ mô tả một quy trình không có thật. Khi Ohana review thật land thì
              thêm cột lúc đó, kèm role + queue + UI.
  Lập luận gốc (giữ lại):
  D10 khai `profile_status` là BẮT BUỘC, lý do: human-in-loop áp cho persona chứ
  không chỉ cho từng reply. Lập luận đó đúng. Nhưng câu chưa trả lời: NGƯỜI DUYỆT
  LÀ AI? Nếu là chính chủ shop thì `approved` chỉ là nút self-confirm — gọi nó là
  "duyệt" là dựng tên cho một quy trình không tồn tại, và về sau sẽ có người đọc
  cột đó như bằng chứng đã qua kiểm duyệt. Nếu là Ohana review thật thì cần role +
  queue + UI ⇒ không phải GĐ0.
  Phương án thay thế: `published_at` (null = chưa phát hành) — mô tả đúng cái đang
  xảy ra, không hứa cái không có.

PRE-1103: Số migration `0007` — kiểm CẢ đĩa LẪN docs/tasks/ lúc execute.
  Trạng thái: ⚠️ VA CHẠM LẦN THỨ TƯ cùng một loại.
    Trên đĩa mới nhất: `0006`. Spec 03 (BLOCKED) hiện giữ chỗ `0007`/`0008`/`0009`.
    Spec 11 lấy `0007` ⇒ spec 03 dịch → `0008`/`0009`/`0010`.
  Command: ls db/migrations/versions/ && grep -rhoE '0[0-9]{3}' docs/tasks/*.md | sort -u
  Luật: số cấp theo thứ tự LAND, không theo thứ tự lập kế hoạch. Alembic nối chuỗi
  bằng `down_revision`, không bằng số trong tên file.

PRE-1104: Có shop nào đang chạy thật không (quyết định backfill).
  Trạng thái: ✅ ĐO 2026-07-20 trên Postgres thật — messages/conversations/customers/
              pending_reply: **0 row, 0 shop_id**. Không cần backfill; `shops` tạo rỗng.
  ⚠️ NHƯNG `embeddings` có 2 shop_id (rác test trong DB dev), và một trong hai là
     **`_platform` — SENTINEL, KHÔNG phải shop**. `parsing/ingest.py` dùng nó làm
     scope cho corpus dùng chung của Ohana AI.
  ⇒ Hệ quả cho tương lai, ghi ra để đừng ai vấp: **KHÔNG được FK `embeddings.shop_id`
     → `shops.id`.** Nghe rất hợp lý ("mọi shop_id đều nên trỏ về shops") và sẽ hỏng
     ngay: `_platform` không bao giờ là một row `shops`. Nếu thật sự muốn FK đó thì
     phải quyết trước: tạo một row `shops` giả cho sentinel (bẩn — một "shop" không
     phải shop lọt vào mọi câu đếm), hay tách corpus nền tảng sang bảng riêng.
     Spec 11 KHÔNG đụng `embeddings`.
```

---

## §7 — Execute Steps

> Mỗi phase: RISK **đề xuất**, Wyatt ký. Floor rule: ALLOWED_FILES giao RISK_PATHS
> (`auth/`, `db/migrations`, `api/admin.py`, `tools/registry.py`) ⇒ tối thiểu `medium`.

### Phase S0 — Schema `shops` + `shop_profile` + validate JSONB lúc ghi

<!-- ADP:PHASE S0 -->
STATUS: DONE
EVIDENCE: commit=8a087c8, gate_exit=0, duration=20s, review=PASS(judge=APPROVE,model=claude-haiku-4-5-20251001,bound=03284d3acd9f,tier=medium), smoke=PASS(bound=03284d3acd9f), ran=2026-07-20T22:10
ROADMAP: GD0-SHOPS
GOAL: `shops` + `shop_profile` tồn tại với composite FK; Postgres TỪ CHỐI profile trỏ shop không tồn tại; `knowledge` JSONB lệch shape bị Pydantic chặn ở đường GHI (không phải đường đọc); migration up→down→up sạch trên Postgres thật.
APPROACH: `Shop(id, name, status, created_at)` + `UniqueConstraint(id)` sẵn có qua PK; `ShopProfile` FK về `shops.id`. Persona theo PRE-1101 (1 cột hay 7 — CHỜ KÝ, không code trước khi có). `knowledge` JSONB validate bằng Pydantic model TẠI `ShopProfileRepo.upsert()` — đặt ở tầng repo chứ không ở API để mọi đường ghi đều đi qua, kể cả script/test. Cap persona kiểm ở CẢ Pydantic LẪN constraint DB: Pydantic cho thông báo lỗi tử tế, DB là thứ không ai bypass được.
ALLOWED_FILES: db/models.py, db/migrations/versions/, db/repos.py, agent/persona.py, tests/test_shops_persona.py, docs/tasks/11-Task-OhanaAISeller-ShopsPersona.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_shops_persona.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (ĐỀ XUẤT — Wyatt ký. Floor: `db/migrations`. Không đề xuất high: bảng MỚI, không backfill, không đổi hành vi gửi/tiền. Nếu PRE-1104 trả > 0 ⇒ nâng high.)
BLOCKED_BY: PRE-1101 ✅ ký · PRE-1102 ✅ ký · PRE-1104 ✅ đo (0 row) · PRE-1103 ✅ kiểm (đĩa=0006 ⇒ lấy 0007)
SMOKE: PASS ref=docs/smokes/11-S0.md
REVIEW: PASS ref=docs/reviews/11-S0-auto-verdict.json
<!-- /ADP -->

1. Test (**RED trước**): (a) FK từ chối profile trỏ shop không tồn tại; (b) `knowledge` lệch shape bị từ chối lúc GHI; (c) persona vượt cap bị từ chối; (d) `ShopProfileRepo(shop_scope='A')` không đọc được profile shop B (trả None, không raise); (e) migration up→down→up.
2. Model + migration `0007`.
3. Pydantic model cho `knowledge` + wire vào repo.
4. **STOP+WAIT**.

### Phase S1 — Onboard shop thật → JWT mang `shop_id` đã verify

<!-- ADP:PHASE S1 -->
STATUS: IN_PROGRESS
ROADMAP: GD0-SHOPS
GOAL: `POST /admin/shops` tạo shop thật (admin-only); JWT phát ra mang `shop_id` của một row `shops` TỒN TẠI; JWT khai `shop_id` không có trong `shops` bị TỪ CHỐI; test cross-shop: JWT shop A không đọc được data shop B.
APPROACH: Onboard endpoint vào `api/admin.py` (đã có `require_admin`). Điểm cốt lõi: `auth/identity.py` thôi tin `shop_id` chỉ vì nó có chữ ký hợp lệ — phải đối chiếu với `shops`. Đây là đổi hành vi của ranh giới tenant, không phải thêm endpoint. `api/mock_auth.py` GIỮ LẠI cho dev nhưng thôi là nguồn `shop_id` duy nhất; fixture shop của nó phải được seed vào `shops` khi `OHANA_ENV=dev`, nếu không dev env vỡ im lặng.
ALLOWED_FILES: api/admin.py, auth/identity.py, api/mock_auth.py, db/repos.py, db/shop_repo.py, app/main.py, api/inbox.py, api/chat.py, tests/test_shops_persona.py, tests/test_tenant_isolation.py, docs/tasks/11-Task-OhanaAISeller-ShopsPersona.md, docs/reviews/, docs/smokes/
ALLOWED_FILES_AMEND: Wyatt duyệt 2026-07-20 — 3 file thêm, cả ba BỊ ÉP CƠ HỌC, không phải mở scope tuỳ ý.
  · `db/shop_repo.py` (mới): gate ranh giới spec 07 (`test_chat_module_cannot_reach_the_customer_send_path`)
    ĐỎ khi `ShopRepo` nằm trong `db/repos.py` — bao đóng thành `api.chat → auth.identity → db.repos →
    db.models.PendingReply`, tức đường chat nội bộ nối tới module sở hữu hàng đợi gửi khách. Gate đúng;
    tách module làm phụ thuộc hẹp lại đúng bằng thứ auth thật sự cần (`Shop`).
  · `api/inbox.py` + `api/chat.py`: dependency thành async ⇒ annotation phải là
    `Callable[..., Identity | Awaitable[Identity]]`. mypy chặn ở call site, không có đường vòng.
  · `app/main.py`: 3 call site — chính là nơi wire, không thể không đụng.
GATE: .venv/bin/python -m pytest tests/test_shops_persona.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: high (✅ WYATT KÝ 2026-07-20. Floor cho `auth/` là medium, nhưng ký **high**: phase này ĐỔI HÀNH VI của ranh giới tenant — thứ mà CLAUDE.md §3 gọi là "bất biến cốt lõi". Sai ở đây không hỏng một tính năng, nó hỏng sự cách ly giữa mọi shop. high ⇒ per-step confirm + Wyatt đọc diff sync + human review artifact.)
BLOCKED_BY: S0 DONE
SMOKE: PASS ref=docs/smokes/11-S1.md
REVIEW: PASS ref=docs/reviews/11-S1-auto-verdict.json human=docs/reviews/11-S1-human.md
<!-- /ADP -->

1. Test (**RED trước**): (a) onboard tạo row + trả shop_id; (b) non-admin → 403; (c) JWT với `shop_id` không có trong `shops` → từ chối; (d) cross-shop đọc → rỗng; (e) `OHANA_ENV=dev` seed fixture shop, ngoài dev thì KHÔNG.
2. Onboard endpoint.
3. `auth/identity.py` đối chiếu DB.
4. `mock_auth` seed fixture shop (dev-gated, fail-loud ngoài dev).
5. **STOP+WAIT (per-step nếu Wyatt ký high)**.

### Phase S2 — `lookup_size` / `lookup_shipping` + `build_persona_prompt`

<!-- ADP:PHASE S2 -->
STATUS: TODO
ROADMAP: GD0-SHOPS
GOAL: `lookup_size(160,50)=="M"` assert được không cần LLM; thiếu data ⇒ `not_found` TƯỜNG MINH (không rỗng, không None); cả hai tool scope `shop_id` từ handler-arg, KHÔNG từ `parameters`; `build_persona_prompt` cap cứng và không bao giờ nhả chuỗi "Ohana".
APPROACH: `tools/shop_kb.py` theo shape `tools/wiki.build_tool`. `ToolHandler` nhận `(user_id, shop_id, args)` và `shop_id` KHÔNG được có trong `parameters` — đó là lý do LLM không chĩa tool sang shop khác được; giữ nguyên bất biến đó. `not_found` là giá trị trả về TƯỜNG MINH (`{"success": True, "result": "not_found"}` chứ không phải `success: False`) — thiếu data là câu trả lời hợp lệ, không phải lỗi hệ thống; nhầm hai cái này làm confidence gate đọc sai tín hiệu. `build_persona_prompt` là hàm THUẦN (profile → str), không chạm DB, không chạm LLM — để test được bằng assertion tất định.
ALLOWED_FILES: tools/shop_kb.py, tools/registry.py, agent/persona.py, app/main.py, tests/test_shops_persona.py, docs/tasks/11-Task-OhanaAISeller-ShopsPersona.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_shops_persona.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (ĐỀ XUẤT — Wyatt ký. Floor: `tools/registry.py`. Không high: không đổi hành vi gửi khách, không chạm tiền.)
BLOCKED_BY: S0 DONE
SMOKE:
<!-- /ADP -->

1. Test (**RED trước**): (a) `lookup_size(160,50)=="M"` trên fixture; (b) ngoài bảng ⇒ `not_found` tường minh; (c) shop chưa có `size_chart` ⇒ `not_found`, KHÔNG nổ; (d) `shop_id` không xuất hiện trong `parameters` của cả 2 tool (đọc `Tool.parameters`, đừng tin docstring); (e) tool scope shop A không đọc data shop B; (f) `build_persona_prompt` cap đúng; (g) persona chứa chữ "Ohana" ⇒ prompt KHÔNG mang nó sang.
2. `tools/shop_kb.py` + register trong `app/main.py`.
3. `agent/persona.py`.
4. **STOP+WAIT**.

### Phase S3 — Đánh dấu spec 03 Phase 1 SUPERSEDED + đóng vòng roadmap

<!-- ADP:PHASE S3 -->
STATUS: TODO
ROADMAP: GD0-SHOPS
GOAL: `03:1` mang `STATUS: CANCELLED` + dòng trỏ sang spec 11; L3 sinh lại không còn map `GD0-SHOPS → 03:1`; L1 §4.1 ghi work item mới cho `Drafter` (§1.3).
APPROACH: ADP v2.2 quy định phase bị vô hiệu hoá bởi thay đổi kế hoạch ⇒ `CANCELLED`, **KHÔNG xoá** — xoá là mất dấu vết vì sao từng có nó. Ghi kèm lý do blocker hết hạn (PRE-007 ACCEPTED 2026-07-19) để lần sau ai đọc spec 03 không tưởng nó vẫn đang chờ. L1 là tầng NGƯỜI viết (§5 CLAUDE.md) nên bước thêm work item `Drafter` phải do Wyatt duyệt nội dung, không phải máy sinh.
ALLOWED_FILES: docs/tasks/03-Task-GD0-AcceptanceBackfill.md, docs/tasks/11-Task-OhanaAISeller-ShopsPersona.md, docs/ROADMAP.md, docs/memory/KNOWN_ISSUES.md, docs/reviews/, docs/smokes/
GATE: bash .claude/tools/adp-roadmap.sh "$PWD" && grep -q "CANCELLED" docs/tasks/03-Task-GD0-AcceptanceBackfill.md
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && bash .claude/tools/adp-roadmap.sh "$PWD"
RETRY: 0/3
RISK: low (ĐỀ XUẤT — Wyatt ký. ALLOWED_FILES toàn docs, KHÔNG giao RISK_PATHS ⇒ floor rule không kích hoạt. Diff docs-only máy verify được.)
BLOCKED_BY: S1 DONE, S2 DONE
SMOKE:
<!-- /ADP -->

1. `03:1` → `CANCELLED` + lý do + trỏ spec 11.
2. L1: thêm work item `Drafter` (Wyatt duyệt nội dung).
3. Sinh lại L3.
4. **STOP+WAIT**.

---

## §8 — DB Changes

- **Alembic `0007` (S0):** `shops(id TEXT PK, name TEXT, status TEXT, created_at TIMESTAMPTZ)` + `shop_profile(shop_id TEXT PK→shops.id, persona_md TEXT CHECK(length ≤ 2000), knowledge JSONB, published_at TIMESTAMPTZ NULL, updated_at TIMESTAMPTZ)`.
- Cap persona: CHECK constraint ở tầng DB **cộng** Pydantic ở tầng ghi. Hai lớp vì chúng hỏng khác nhau — Pydantic bị bypass bởi raw SQL, CHECK bị bypass bởi không ai.
- ⚠️ `shop_profile.shop_id` là PK **và** FK: đúng một profile mỗi shop. Nếu sau này cần versioning thì đó là bảng khác, không phải nới PK này.
- NEVER edit migration đã apply — thêm revision mới.

---

## §10 — Post-checks

```bash
.venv/bin/python -m pytest tests/ -q -m 'not live'
.venv/bin/mypy app agent retrieval parsing storage db bridge tools api auth
.venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
alembic upgrade head && alembic downgrade -1 && alembic upgrade head   # trên Postgres THẬT
```

⚠️ **Chạy pytest xong thì schema alembic bị bẩn** — `fresh_db` drop/create từ `Base.metadata` trên cùng DB nhưng không đụng `alembic_version`. Muốn verify chuỗi migration phải reset schema trước; nếu `drop schema public cascade` thì nhớ `CREATE EXTENSION vector` lại bằng superuser (`drnick`, KHÔNG phải `postgres`). Xem `docs/smokes/10-H0.md` §4.

---

## §11 — Deliverables

`db/models.py` (+2 model) · `db/migrations/versions/0007_shops_profile.py` · `db/repos.py` (+`ShopProfileRepo`) · `agent/persona.py` · `tools/shop_kb.py` · `api/admin.py` (+2 route) · `auth/identity.py` · `api/mock_auth.py` · `tests/test_shops_persona.py` · `docs/tasks/03-…` (CANCELLED) · `docs/ROADMAP.md`.

Commit: `adp/11-Task-OhanaAISeller-ShopsPersona phase-<id>: checkpoint` (do `adp-checkpoint.sh` viết).

---

## §12 — Constraints

🚫 **KHÔNG code trước khi PRE-1101 được ký** — số cột persona quyết định cả migration lẫn API. Đoán rồi sửa = migration thứ hai.
🚫 **KHÔNG tự hạ RISK của S1.** Nó đổi hành vi ranh giới tenant.
🚫 **KHÔNG cho kiến thức shop đi RAG** (D8/D9).
🚫 **KHÔNG validate `knowledge` lúc đọc** — phải chặn ở đường ghi.
🚫 **KHÔNG để `not_found` thành `success: False`** — thiếu data là câu trả lời hợp lệ, không phải lỗi.
🚫 **KHÔNG đọc test identity-leak của S2 như bằng chứng AI không lộ danh tính** — nó chỉ chứng minh phần tất định.
🚫 **KHÔNG xoá spec 03 Phase 1** — `CANCELLED`, giữ dấu vết.
🚫 Self-certify DONE ngoài `adp-checkpoint.sh`.

**Ghi nợ ra L1 (S3 bước 2):** `Drafter` implementation chưa có work item nào sở hữu. Không có nó thì persona của spec này không có ai tiêu thụ, và AI Seller vẫn chưa tồn tại.

---

## §13 — Tracking

| Phase | Nội dung | STATUS | RISK (đề xuất) |
|---|---|---|---|
| S0 | Schema `shops` + `shop_profile` + validate JSONB lúc ghi | TODO | medium |
| S1 | Onboard → JWT `shop_id` đã verify | TODO | **high** (ký) |
| S2 | `lookup_*` + `build_persona_prompt` | TODO | medium |
| S3 | `03:1` CANCELLED + L1 thêm `Drafter` | TODO | low |

---

## §14 — Open questions (Wyatt quyết — spec KHÔNG tự chốt)

**Q1 · PRE-1101** ✅ ĐÓNG — 1 cột `persona_md`, cap 2000. (Wyatt 2026-07-20)

**Q2 · PRE-1102** ✅ ĐÓNG — `published_at`, bỏ `profile_status`/`approved_by`. (Wyatt 2026-07-20)

**Q3 · RISK của S1** ✅ ĐÓNG — **high** đã ký. ⇒ per-step confirm + Wyatt đọc diff sync + human review artifact (auto-verdict KHÔNG đủ). (Wyatt 2026-07-20)

**Q4 · `Drafter` là work item của ai?** Không có trong L1 §4. Persona không có người tiêu thụ cho tới khi nó tồn tại. Đề nghị Wyatt cấp ID bền trước khi S3 chạy.

**Q5 · Cache `shop_profile`?** Chưa có, nhưng sẽ có (đọc mỗi lượt). Nếu quyết cache ở spec này thì phải kèm test 2 shop song song; nếu để sau thì ghi vào KNOWN_ISSUES để không ai thêm cache không key theo `shop_id`.
