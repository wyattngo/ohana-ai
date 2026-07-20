# ONFA Triage Brief v3 / Bản phân loại task

<!-- Handoff marker: brief-formatter v3, pipeline=SPRINT -->
<!-- Project: ohana-ai (KHÔNG phải ONFA Wallet / DrNick). ADP v2.3 isolated tại ohana-ai/.claude/ -->

---

## ✅ 0. Provenance — ĐÃ RE-VERIFY trên HEAD (2026-07-20)

> **Cập nhật 2026-07-20:** §0 bản đầu cảnh báo brief này sinh từ **tarball `codeload` của `main` lúc 01:10**, lệch với L3 STATUS 08:44. Đã audit lại on-disk trên HEAD thật `e8a5952` (worktree sạch). Kết quả bên dưới.

**Snapshot 01:10 sai ở 2 chỗ:**

| Trường | Brief nói (01:10) | HEAD `e8a5952` |
|---|---|---|
| Phase gate-passed | 24/34 | **25/35** — spec `09:C0` đã checkpoint |
| Migration mới nhất (F2) | `0004` | **`0005_conversation_unique.py`** |

**Phần còn lại của brief đã verify ĐÚNG** — số dòng `api/chat.py` 160 / `orchestrator.py` 103 / `inbox.py` 103 khớp từng dòng; F2 (không có bảng `shops`, 6 model), F7 ([parsing/ingest.py:58](parsing/ingest.py:58) hardcode namespace + [tools/wiki.py:43](tools/wiki.py:43) hardcode `shop_scope`), F8 ([api/admin.py:126](api/admin.py:126) `shop_id` từ body, identity bind `_admin` không dùng), F9 — tất cả tái lập được.

**⚠️ Một tiền đề PHẢI bác bỏ trước khi dùng brief này làm input cho spec:**

Đường AI Seller hiện **zero traffic**, không phải "đang chạy":
- [api/webhook.py](api/webhook.py) **không được mount** trong `app/main.py` (`include_router` chỉ có `inbox`, `mock_auth`, `admin`, `chat`).
- `Drafter` là Protocol rỗng — **zero implementation** toàn repo.
- Bảng `Message` **chưa có đường code nào ghi vào** (`grep "Message("` ngoài định nghĩa model = 0 hit).

⇒ Mọi lập luận kiểu *"tin nhắn khách đã đi qua Together US rồi nên vấn đề pháp lý đang OPEN"* là **SAI**. PII khách chưa từng rời máy. **D6 hoãn Bước 1 vì lý do residency vẫn đứng vững**, và đúng hơn: import lịch sử sẽ là **lần đầu tiên** PII khách VN đi qua US, không phải "đổi khối lượng".

**EN:** Re-verified on-disk at HEAD `e8a5952`. Two corrections to the 01:10 snapshot: phase count is 25/35 (spec `09:C0` landed) and the latest migration is `0005`, not `0004`. Everything else in §2.3 reproduces exactly. Critical: the AI Seller path carries **zero traffic** — `api/webhook.py` is not mounted, `Drafter` has no implementation, and nothing writes to `Message`. Any argument that customer PII already flows through Together US is false; D6's residency-based deferral of Step 1 stands, and the import would be the *first* such flow, not a scale-up of an existing one.

---

## 1. Goal / Mục tiêu

**VI:** Audit lại `ohana-ai` trên HEAD thật để xác nhận (hoặc bác bỏ) 9 phát hiện ở §2.3, rồi patch L1 `docs/ROADMAP.md` theo 4 mục Wyatt đã duyệt (§4.3). **Không code, không migration, không spec execution scaffold trong task này.**

**EN:** Re-audit `ohana-ai` at real HEAD to confirm or refute the 9 findings in §2.3, then patch L1 `docs/ROADMAP.md` per the four approved edits in §4.3. No code, no migrations, no execution scaffold in this task.

---

## 2. Context / Bối cảnh

**VI:**

### 2.1 Sản phẩm — hai persona, KHÔNG phải một

Wyatt chốt tách rõ hai thứ:

| | **Ohana AI** | **AI Seller** |
|---|---|---|
| Ai nói chuyện | User ↔ app Ohana | Khách hàng ↔ shop |
| Xưng danh | "Ohana AI" | **Là shop** — không bao giờ lộ Ohana |
| Trả lời về | Dịch vụ / tính năng / gói cước app Ohana | Sản phẩm, giá, tồn kho, chính sách của shop |
| Surface hiện tại | `api/chat.py` | `api/inbox.py` + `agent/orchestrator.py` |

### 2.2 Trạng thái persona trong code (theo snapshot 01:10)

- **Đúng 1 chỗ** có system prompt trong toàn repo: `api/chat.py:37` `_SYSTEM_PROMPT` — hardcode module-level, 4 câu, **không có tên**, chỉ "trợ lý AI cho người bán hàng online tại Việt Nam".
- `agent/orchestrator.py` (103 dòng) và `api/inbox.py` (103 dòng): **không có prompt nào**. `Drafter` là Protocol trống, chưa có implementation thật.
- **Zero test** chạm `_SYSTEM_PROMPT`. Không có eval nào cho identity/tone.

### 2.3 Sáu phát hiện cần Claude Code re-verify

| # | Phát hiện | Bằng chứng ở snapshot |
|---|---|---|
| **F1** | Quan hệ "nhà máy ↔ module" đang **ngược**. Ohana AI (`api/chat.py`, 160 dòng, stateless, 0 tool, 0 RAG, 0 history, `grounded=False` cứng) là lát mỏng nhất repo; đường seller mới là phần dày. Và `tests/test_chat_endpoint.py:434` **cấm cơ học** chat với tới đường gửi khách (forbidden: `agent.policy_gate`, `agent.orchestrator`, `channels.zalo`, `bridge.zalo_sender`, `PendingReply`, mọi module tên chứa `sender`). | `api/chat.py`, `tests/test_chat_endpoint.py:434` |
| **F2** | **Bảng `shops` không tồn tại.** `db/models.py` có đúng 6 model: `Message`, `Embedding`, `Customer`, `Conversation`, `OrderDraft`, `PendingReply`. `shop_id` là `Text` trần khắp nơi. ~~Migration mới tới `0004`~~ → **`0005` trên HEAD** (xem §0). ⇒ Bước 2 không có nơi để đọc. | `db/models.py`, `db/migrations/versions/` |
| **F3** | Bước 1 và Bước 2 **không có trong roadmap**. Rà hết §4.1–§4.4 (35 work item): không item nào về import lịch sử chat hay derive tông giọng. `GD2-DISCOVERY` là VLM enrich **catalog sản phẩm**, không phải giọng shop. L3 hiện `Unplanned = rỗng`; thêm code trước khi thêm L1 sẽ tạo drift và spine chặn. | `docs/ROADMAP.md` §4, `ROADMAP-STATUS.md` |
| **F4** | **Từ "wiki" đã trôi thành hai nghĩa.** Ý định gốc của Wyatt: wiki = kho RAG của **Ohana AI**. **Code đứng về phía đó** — `parsing/ingest.py:18-19` sentinel `_platform` + namespace `platform_wiki`; `tools/wiki.py:1` gọi là "the platform's shared wiki corpus"; đường đọc `:43-44` hardcode cả `shop_scope` lẫn `namespaces`. **Nhưng roadmap + docs đã trôi sang nghĩa "corpus của shop"** — `ROADMAP.md` §3 gán `GD0-WIKI` cho intent 4/6/7/8 (size chart, thời gian giao, COD, uy tín shop); `KNOWN_ISSUES.md:240-243` viết thẳng "corpus thật **của seller**", "văn phong **seller** thật". Một cái tên, hai nghĩa, không ai ghi lại lúc nó trôi. | `parsing/ingest.py:18-19`, `tools/wiki.py:1,43-44`, `ROADMAP.md` §3, `KNOWN_ISSUES.md:240-243` |
| **F5** | Corpus Ohana bị xếp nhầm **`external`, chờ Tân** (`GD0-WIKI` class = external / PRE-003 = "Wiki docs source (Notion/Drive/markdown) + format"). Nhưng nội dung về **dịch vụ Ohana** thì Wyatt + Anh Sơn viết được, không dính Tân. ⇒ ưu tiên số 1 đang bị khoá sau một người không liên quan. | `ROADMAP.md` §4.1, `KNOWN_ISSUES.md:47-53` |
| **F7** | **Đường wiki per-shop là write-only, hỏng im lặng.** `parsing/ingest.py:34` cho `shop_id` là tham số và docstring `:5-6` hứa "per-shop wiki extensions can land later by passing a real shop_id"; `api/admin.py:126` **đã expose field đó ra API**. Nhưng `:58` `namespace=PLATFORM_WIKI_NAMESPACE` **hardcode**, và đường đọc `tools/wiki.py:43-44` cứng cả `shop_scope` lẫn `namespaces`. ⇒ POST `/admin/wiki/ingest` với `shop_id="shop_123"` ghi thành công, trả `{"success": true, "chunks": N}`, **không đường code nào đọc lại được**. Zero test phủ (`tests/test_wiki_rag.py:144` ghi thẳng `Embedding` với `namespace="chat"`, không qua `ingest_wiki`). | `parsing/ingest.py:34,58`, `api/admin.py:126,152`, `tools/wiki.py:43-44` |
| **F8** | **`shop_id` đọc từ request body** — vi phạm anti-pattern §6 của chính CLAUDE.md (`🚫 Đọc user_id/shop_id/role từ request body/webhook thay vì verified JWT`). `api/admin.py:126` + `:152`; identity bind vào `_admin` (underscore = không dùng để ràng buộc). Hiện chỉ `require_admin` gọi được nên rủi ro thấp — nhưng nếu import per-shop land, đây thành đường ghi chính và thành lỗ thật. | `api/admin.py:126,145,152`, `CLAUDE.md` §6 |
| **F9** | **Không có index vector.** `KNOWN_ISSUES.md:244-245` tự ghi: chưa có ivfflat/hnsw, "Chưa ai nhận". Corpus Ohana AI là platform-wide, lớn hơn corpus per-shop ⇒ đặt Ohana AI làm ưu tiên thì cái này chặn sớm hơn dự kiến. | `KNOWN_ISSUES.md:244-245` |
| **F6** | Bước 1 đâm vào ADR đã ký. `docs/adr/2026-07-18-hosting-region.md` Status **ACCEPTED**, deployment-region = **Together US serverless**. ADR tự ghi: Legal path (Open-Q #4) **không đóng bằng chữ ký này**, nghĩa vụ pháp lý **chưa có chủ**. Import lịch sử chat khách VN = PII bên thứ ba, hàng loạt, embed qua US. Khác bậc so với từng tin lẻ hôm nay. | `docs/adr/2026-07-18-hosting-region.md` |

### 2.4 Nền móng đang ĐÚNG — không đụng vào

- Hạ tầng dùng chung đã đúng hình: `LLMClient` ABC, `Embedder` ABC (`embed_query`/`embed_documents` bất đối xứng cho e5), `PgvectorRetriever(shop_scope=)`, `tools/registry.Tool`, `channels/base` Protocol.
- Multi-tenant vững: `shop_id` NOT NULL mọi bảng, composite FK, scope SQL-level không post-filter.
- Human-in-loop cứng: `policy_gate.decide` 4 rule theo precedence, `orchestrator` đúng 2 nhánh, không back-door.
- `GD0-SHOPS` **đã có** trong L1 §4.1, class `internal`, không chờ ai. L3: `⬜ TODO 0/1`, phase trỏ `03:1`.

**EN:** Two distinct personas: Ohana AI (user ↔ app, identifies as Ohana, answers about the Ohana product) and AI Seller (customer ↔ shop, speaks *as the shop*, never reveals Ohana). Exactly one system prompt exists repo-wide (`api/chat.py:37`), unnamed and generic; the seller path has none. Six findings F1–F6 above need re-verification at HEAD: inverted factory/module relationship enforced by an import-graph gate, no `shops` table, both of Wyatt's steps absent from the roadmap, one wiki namespace serving two incompatible purposes, the Ohana corpus wrongly classed as third-party-blocked, and the import step colliding with a signed residency ADR whose legal open-question has no owner. The shared infrastructure, multi-tenant scoping, and human-in-loop gate are correct — do not touch them.

---

## 3. Classification / Phân loại

- **Risk:** High
- **Workflow mode:** AUDIT
- **Pipeline mode:** SPRINT

**Reason VI:** Không chạm cột tài chính ⇒ không Financial-critical. Nhưng output của nó dẫn tới migration `shops` + đụng `RISK_PATHS` (`db/migrations`, `api/chat.py`, `agent/orchestrator.py`) và F4 là loại lỗi retrieval âm thầm ⇒ High. Task này **chỉ audit + sửa L1**, nhiều module, nhiều file đọc ⇒ SPRINT chứ không SIMPLE. IMPLEMENT bị chặn có chủ ý: chưa được viết code cho tới khi L1 có ID.

**Reason EN:** No financial columns, so not Financial-critical — but it drives a `shops` migration, touches declared RISK_PATHS, and F4 is a silent-retrieval-corruption class of bug, hence High. Audit + L1 edits only, spanning many modules: SPRINT, not SIMPLE. IMPLEMENT is deliberately withheld until durable IDs exist in L1.

---

## 4. Critical gaps / Khoảng trống thông tin

**VI:**

### 4.1 Đã chốt (Wyatt, phiên này) — coi là quyết định, KHÔNG hỏi lại

| # | Quyết định |
|---|---|
| **D1** | **Sườn chung = tầng thư viện hạ tầng dùng chung.** Ohana AI và AI Seller là **hai runtime NGANG HÀNG** cùng đứng trên nó. **KHÔNG** phải quan hệ cha-con, **KHÔNG** một orchestrator dùng chung với nhánh `if persona == ...`. Gate import-graph ở `tests/test_chat_endpoint.py:434` giữ nguyên hiệu lực. |
| **D2** | Bước 1 + Bước 2 phải vào L1 `docs/ROADMAP.md` §4 với ID bền + cột Class **trước khi** viết bất kỳ dòng code nào. |
| **D3** | ~~Tách corpus làm hai, `GD0-WIKI` giữ `external`.~~ **SUPERSEDED bởi D7 — Wyatt đính chính 2026-07-20.** Không tách: `platform_wiki` **là** corpus của Ohana AI, đúng như ý định gốc. Kiến thức shop **không đi RAG**. |
| **D4** | Build `GD0-SHOPS` — bảng `shops` + `shop_profile`. Là điều kiện cần của Bước 2. |
| **D5** | Bước 2 chạy với profile **nhập tay** trước. Ship được ngay, không chờ ai, và tạo sẵn ground truth cho eval tone. |
| **D6** | Bước 1 (import lịch sử/kho hàng) **chỉ khởi động sau khi** Open-Q #4 của ADR residency có chủ. Không phải quyết định kỹ thuật. |
| **D7** | **Phân tầng theo HÌNH DẠNG DỮ LIỆU, không theo intent.** Tầng 1 *fact động* (đổi theo thời gian, nguồn ngoài) → **tool live lookup**, intent 1/2/11. Tầng 2 *fact tĩnh có cấu trúc* (ánh xạ tham số → giá trị) → **JSONB trên `shop_profile` + hàm tra cứu tất định**, intent 4/5/6. Tầng 3 *văn xuôi / tông giọng* (không tham số hoá được) → **text field ráp thẳng system prompt**, intent 7/8. |
| **D8** | **AI Seller KHÔNG có vector store nào ở GĐ0.** Ohana AI giữ RAG (`platform_wiki`) vì đúng hình dạng: nhiều văn xuôi, một corpus, không tham số hoá được. Seller path = zero embedding. Ngoại lệ đã biết: intent 3 (discovery sản phẩm) là semantic thật — `GD2-DISCOVERY`, **GĐ2, không phải GĐ0**. Per-shop RAG cho văn xuôi chỉ xây khi có shop thật chứng minh không nhét vừa field (kỷ luật "không generic sớm" của `channels/base.py`). |
| **D9** | **Size chart / bảng ship KHÔNG được đi RAG** — lý do an toàn, không phải tối ưu: (a) `parsing/chunk.py` cắt `max_chars=800` sẽ **cắt giữa bảng**, chunk mất cột; (b) cosine similarity giữa `"1m6 50kg"` và chunk bảng số gần như vô nghĩa; (c) **RAG không bao giờ nói "không biết"** — luôn trả k chunk gần nhất, trong khi hàm tra cứu trả `not_found` dứt khoát, và đó chính là tín hiệu confidence-gated escalation (§6.4) cần. Nhất quán với §2.3 đã ký: "fact → tool, cấm đoán". Bonus: hàm tất định eval được bằng assertion thật (`lookup_size(160,50) == "M"`), không cần LLM-as-judge. |
| **D10** | **Schema `shop_profile` đã chốt** (thay thế mục "chưa duyệt" ở §4.2 bản trước):<br>`shops`: `id · name · status · created_at`<br>`shop_profile` — *persona (text, VÀO prompt)*: `display_name · industry · tone_notes · policy_return · policy_cod · policy_shipping_note · greeting`<br>— *knowledge (jsonb, KHÔNG vào prompt)*: `size_chart · shipping_zones`<br>— *gate*: `profile_status(draft\|approved) · approved_by · approved_at`<br>Hai tool nội bộ đọc JSONB, scope `shop_id`: `lookup_size(...)`, `lookup_shipping(...)` — cả hai trả `not_found` tường minh. `profile_status` **bắt buộc**: human-in-loop áp cho **persona**, không chỉ cho từng reply; chưa `approved` ⇒ AI Seller chạy persona mặc định. |

### 4.3 Bốn patch L1 Wyatt đã duyệt — deliverable của task này

| # | Patch vào `docs/ROADMAP.md` |
|---|---|
| **L1-1** | `GD0-WIKI`: class **`external` → `internal`**. Mô tả đổi thành *corpus Ohana AI* (tính năng / gói cước / cách dùng / chính sách nền tảng). **Gỡ dependency PRE-003 / Tân.** |
| **L1-2** | §3 intent table: intent **4** và **6** đổi cột *Roadmap ID* từ `GD0-WIKI` → **`GD0-SHOPKB`**; intent **7** và **8** → **`GD0-SHOPS`**. |
| **L1-3** | Thêm work item **`GD0-SHOPKB`**, class **`internal`** — `size_chart` / `shipping_zones` + hai hàm tra cứu tất định. Đọc từ DB của ta, **không cần API Tân**. Đây là lần unblock thứ hai cùng dạng với L1-1. |
| **L1-4** | `GD0-TOOLS`: **giữ nguyên `external`** — product / order / account từ API Tân (PRE-002), khác bản chất với hai mục trên. Không đụng. |

Hệ quả kỹ thuật của D7–D10 (ghi để spec sau kế thừa, **không thực thi trong task này**): F7 giải bằng cách **gỡ bỏ** nhánh per-shop RAG — bỏ tham số `shop_id` khỏi `ingest_wiki` + `WikiIngestRequest`, để `_platform` thành hằng số thật — việc đó đóng luôn F8. F9 thu hẹp về đúng một corpus (Ohana AI).

### 4.2 Còn thiếu — Claude Code đánh dấu, KHÔNG tự quyết

- ~~Schema `shop_profile`~~ — **ĐÃ CHỐT ở D10.**
- ~~Tên namespace corpus Ohana~~ — **ĐÃ ĐÓNG:** `platform_wiki` giữ nguyên, nó vốn đã là corpus Ohana AI (F4). Không tạo namespace mới.
- **Ngân sách token của persona**: prompt hôm nay ~134 token (`api/chat.py:123`). Ráp toàn bộ text field của `shop_profile` vào mỗi lượt đổi hẳn kinh tế token. Cần **cap cứng độ dài phần persona** — con số cụ thể chưa chốt. Đây cũng là lúc `token_cached` mà `api/chat.py:130` đang log bắt đầu có ý nghĩa để đo.
- **Chat stateless**: `api/chat.py` gửi đúng 1 system + 1 user mỗi request, không history. Bảng `Message` đã có (`role`: user|assistant|seller|system) nhưng chat **không dùng**. Nhân cách nhất quán đa lượt cần history — **chưa quyết** có vào scope hay tách phase riêng.
- **Tone/Voice eval không có ground truth per-shop**: `ROADMAP.md` §6.1 định nghĩa dimension này là "đúng giọng người bán VN" (generic), trong khi Wyatt muốn giọng *của shop này*. Gap chưa có chủ.
- **Zalo/FB read-history API**: khả năng đọc lịch sử quá khứ, retention, scope quyền — **UNVERIFIED**. Chưa ai đọc docs Zalo OA thật. Không được đưa vào spec cho tới khi verify.
- **Doc drift cần phân xử**: `CLAUDE.md` §7 ghi `test_wiki_rag_live` 4 PASS trên e5 (2026-07-19); `KNOWN_ISSUES` ISSUE-016 vẫn OPEN và mô tả bằng `OPENAI_API_KEY` (văn bản có trước spec 08 swap). Một trong hai sai.
- **`GD0-RESIDENCY` uncovered**: L3 báo `⚪ chưa có spec`, nhưng ADR PRE-007 đã ACCEPTED. L1 có item, không spec nào nhận. Cần giải thích hoặc đóng.

**EN:** Decisions D1–D10 are settled and must not be re-litigated. In short: the shared skeleton is a shared *library* layer with two peer runtimes, never a parent/child or a persona branch inside one orchestrator; both steps enter L1 with durable IDs before any code; **D3 is superseded by D7** — the wiki is not split, `platform_wiki` *is* Ohana AI's corpus as originally intended, and shop knowledge does not use RAG at all; instead knowledge is tiered by *data shape* — live tools for dynamic facts, JSONB plus deterministic lookup functions for structured static facts (size charts, shipping zones), plain text fields for prose and voice; the AI Seller has no vector store in GĐ0 (product discovery is GĐ2); size charts must never go through RAG because chunking splits tables, embedding similarity over numeric tables is meaningless, and RAG can never answer "I don't know" — which is precisely the signal confidence-gated escalation depends on; the `shop_profile` schema is fixed, including a mandatory `profile_status` approval gate that extends human-in-loop from individual replies to the persona itself. The deliverable is the four L1 patches in §4.3. Still open and not for Claude Code to decide: the persona token budget cap, whether chat history enters scope, per-shop tone ground truth, Zalo/FB read-history feasibility (unverified — do not spec it), a doc conflict between CLAUDE.md §7 and ISSUE-016, and `GD0-RESIDENCY` being L1-listed but spec-uncovered.

---

## 5. Quick prompt / Prompt nhanh

Delegated to `onfa-orchestrator`. Scenario hint: **audit** (Python/FastAPI, `ohana-ai`, không phải ONFA Wallet).

Ràng buộc bắt buộc chuyển tiếp xuống mọi step:

1. **Audit on-disk trước.** Không tin snapshot trong brief này — nó đã lệch ít nhất một phase (§0). Re-verify **F1–F9** bằng lệnh thật trên HEAD. F7/F8 có số dòng cụ thể: xác nhận từng dòng, đừng tin trích dẫn.
2. **Không code, không migration, không spec execution scaffold** trong task này. Deliverable = báo cáo audit F1–F9 + **4 patch L1 ở §4.3**, không hơn.
3. **Không sửa** `docs/ROADMAP-STATUS.md` (L3 máy sinh).
4. **Không tự quyết** bất kỳ item nào ở §4.2.
5. Không claim DONE ngoài `adp-checkpoint.sh`.

---

## 6. Next skill / Skill kế tiếp

**Skill:** `onfa-orchestrator`
**Reason VI:** Pipeline SPRINT + mode AUDIT, đa module, đọc nhiều file, deliverable là báo cáo + patch tài liệu. Sau khi L1 có ID bền, `GD0-SHOPS` và corpus Ohana mới đủ điều kiện đi tiếp qua `onfa-spec-generator`.
**Reason EN:** SPRINT + AUDIT across multiple modules; deliverable is a report plus a documentation patch. Once L1 carries durable IDs, `GD0-SHOPS` and the Ohana corpus item can proceed to `onfa-spec-generator`.
**Invocation:** "Vào orchestrator"
**Alternative:** Repo này chạy **ADP v2.3 riêng** (`ohana-ai/.claude/`), executor khai báo trong manifest là **`drnick-coder`**, không phải chuỗi skill ONFA Wallet. Nếu orchestrator không nhận project này, đi thẳng skill `adp` → `drnick-coder`.
