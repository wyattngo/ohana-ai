# Ohana AI — Tech Build Roadmap (L1: ý định + lý do)

> **Đây là tầng Ý ĐỊNH. File này KHÔNG chứa trạng thái.**
> Tiến trình sinh ra ở [`ROADMAP-STATUS.md`](ROADMAP-STATUS.md) — đừng gõ tay % vào đây.
>
> **Sub-project:** `ohana-ai/` (workspace `localhost/`). Router: [`../CLAUDE.md`](../CLAUDE.md).
> **Owner:** R: Tân (dev lead) · A: Wyatt (fractional CTO — spec approval + RISK tier).
> **Version:** v6 · **Last updated:** 2026-07-21 · Kế thừa nội dung v5 (2026-07-19).
> **Scope:** thuần kỹ thuật. Không tranche/ngân sách/rev-share/legal-process — ở tài liệu thương mại riêng.
>
> **⚑ Nguồn cấu trúc code CHÍNH THỨC:** [`backend-workflow.md`](backend-workflow.md) — Wyatt duyệt 2026-07-21 (DEC-OHANA-05). Đây là mô tả kiến trúc luồng backend đã chốt. **Khi L1 và workflow lệch nhau, workflow THẮNG.** v6 đã hoà giải 6 điểm lệch (§9 change log) — không rename/xoá ID nào (append-only), chỉ **thêm** work item + siết acceptance để bám workflow. Code hiện tại KHÔNG bị đụng bởi bản cập nhật này; các thay đổi hành vi sẽ land qua ADP spec riêng.

---

## 0. Hợp đồng ba tầng (đọc trước khi sửa bất cứ gì)

| Tầng | File | Ai viết | Chứa gì | KHÔNG chứa gì |
|---|---|---|---|---|
| **L1** | `docs/ROADMAP.md` (file này) | **Wyatt** (người) | ý định, lý do, ID bền, acceptance | ❌ STATUS, ❌ %, ❌ ADP phase block |
| **L2** | `docs/tasks/NN-Task-*.md` | senior-engineer → frozen | phase block + trường `ROADMAP: <id>` | ❌ chiến lược |
| **L3** | `docs/ROADMAP-STATUS.md` | **máy** (`adp-roadmap.sh`) | coverage, uncovered, unplanned | ❌ sửa tay |

**Khoá nối** = trường `ROADMAP:` trong mỗi ADP phase block. Không có nó, L3 không tính được gì.

**L1 nằm NGOÀI spec-lock có chủ ý.** `adp_spec_lock_verify` chỉ khoá `SPEC_DIR` (`docs/tasks/`). Nếu kéo L1 vào vùng diff-bound, mỗi lần re-plan giữa sprint sẽ bị checkpoint REFUSE vì DRIFT — tức là máy cấm bạn đổi ý. Ý định phải sửa được mà không xin phép. Đây là ranh giới thiết kế, không phải sơ suất.

**ID là append-only.** Đổi tên một ID = mất toàn bộ lịch sử đối chiếu của nó. Mục bỏ đi thì đánh dấu `RETIRED` kèm DEC, không xoá dòng — vì mẫu số giảm mà không có DEC là tín hiệu gian lận chỉ số (§0.2).

### 0.1 Ba lớp mẫu số

L3 đếm tách bạch, không gộp:

| Lớp | Nghĩa | Vào mẫu số "100%"? |
|---|---|---|
| `internal` | Ta tự làm được, không chờ ai | ✅ **Đây là mẫu số của mục tiêu 100%** |
| `external` | Chờ bên thứ ba (Tân, Meta, hãng audit, provider, luật sư) | ❌ đếm riêng — nếu gộp, chỉ số không bao giờ chạm 100% rồi bị bỏ qua |
| `out-of-scope` | GĐ4 | ❌ không đếm |

### 0.2 Chống gian lận chỉ số

Ta kiểm soát cả tử lẫn mẫu ⇒ xoá một dòng L1 là % tăng. L3 vì vậy ghi lại **lịch sử mẫu số**. Mẫu số `internal` giảm mà không có DEC kèm theo = cảnh báo đỏ, không phải tiến bộ.

---

## 1. Phase map

| GĐ | Technical milestone | Technical gate |
|---|---|---|
| GĐ0 | MVP Wedge: Zalo-only, 1 shop thật, AI suggest + duyệt-gửi, order draft, intent gate | E2E shop thật + credit metering + **eval harness pass** + latency p95 + escalation gate |
| GĐ1 | Payment + Fulfillment cơ bản (1 provider + 1 carrier) | Payment webhook tự chuyển state + vận đơn thật + COD reconcile khớp + state audit log |
| GĐ2 | Đa kênh + Đối soát COD + Analytics + Semantic product discovery | 2 kênh qua abstraction + reconcile đa hãng 100% + product RAG grounded |
| GĐ3 | Billing + Reseller + Hardening | Recurring charge 1 chu kỳ + load target + security audit pass |
| GĐ4 | Financial AI (crypto/BĐS/CK/vàng) | — (ngoài scope, §7) |

**Priority order (mọi GĐ trừ GĐ4):** safety → user trust → stability → growth.

---

## 2. Nguyên tắc chung (áp dụng mọi GĐ)

### 2.1 ADP discipline
1. **ADP v2.3.** Mỗi GĐ ≥ 1 spec `docs/tasks/NN-Task-*.md`. Phase gate-passed = test exit 0 + diff-binding + human sign (RISK:high). Không self-certify.
2. **Prerequisite hard-block trước ship.** Spec block `STATUS: BLOCKED` nếu PRE-* chưa RESOLVED. Không "vá sau".
3. **RISK tier do Wyatt gán,** agent không tự hạ. Money-adjacent / AI-output code → tối thiểu `medium`, thường `high`.
4. **Test parity với production shape.** Mock chỉ để unblock phase-gate; acceptance-DONE cần real endpoint + real shop + real traffic.
5. **SMOKE gate (2026-07-19).** Test đo môi trường TEST; smoke đo môi trường THẬT. Không cái nào thay được cái nào. Sinh ra từ spec 07: 5 lỗi lọt qua 107 test + mypy sạch + 3 vòng review, chỉ lộ khi chạy thật. Format ở `CLAUDE.md §5`.
6. **Land abstraction sớm.** Refactor tax 3-5× nếu đợi GĐ sau: channel, webhook, order state, credit metering, model routing.

### 2.2 AI-layer discipline (bắt buộc cho AI product)
7. **Eval harness là gate, không optional.** Đổi prompt / model / RAG corpus → chạy golden set. Regression gate: không hạ pass-rate dưới threshold. Latency KHÔNG phải bằng chứng chất lượng. Chi tiết §6.1.
8. **Model routing qua abstraction.** Cấm hardcode model id trong orchestrator. Plan tier → model id qua `agent/model_router.py`. PLANS hứa 3 tier = false promise cho tới khi router land. Chi tiết §6.2.
9. **LLM observability, không chỉ latency.** Token/cost per conv, tool-call success, RAG hit-rate, fallback rate, **Manual Override Rate**, trace correlation. Chi tiết §6.3.
10. **Hard grounding cho fact — cấm LLM đoán.** Ranh giới cứng: *fact (tồn kho/giá/phí/trạng thái) → tool; chỉ tone/phrasing → LLM*. Tool miss/không chắc → gợi ý "để shop check lại", KHÔNG bịa số. Mitigation #1 cho oversell + hứa sai.
11. **Confidence-gated escalation = tính năng.** AI phải biết lúc nào **KHÔNG gợi ý**. Chi tiết §6.4.
12. **Untrusted input.** Tin khách = untrusted vào LLM context. `policy_gate` = output-side; cần input-side hardening + tool-call do customer-text trigger qua cùng authorization (shop scope). Xem §8.
13. **Graceful degradation.** LLM down/slow → heuristic fallback server-side + SLO. **Single-provider + fallback**, KHÔNG multi-provider sớm (nhân đôi eval+prompt maintenance; chỉ cân nhắc GĐ3+ nếu uptime data chứng minh cần).

### 2.3 Guardrails — thứ AI KHÔNG được tự quyết (chốt chặn cứng)

| Hành động | Cơ chế bắt buộc | Lý do |
|---|---|---|
| **Xác nhận "đã thanh toán"** | Chỉ **payment webhook** (GĐ1). AI KHÔNG được đọc "em ck rồi" của khách → chuyển state | Nếu không → giao hàng cho đơn chưa trả. Scam vector kinh điển. |
| **Giảm giá / mặc cả** | Rule bounded (freeship threshold đã cấu hình) **hoặc** human. AI chỉ từ chối lịch sự / offer thứ đã cho phép | AI freelance discount = mất margin + tạo tiền lệ. VN mặc cả nặng. |
| **Quyết định hoàn/đổi** | Luôn human. AI chỉ **soạn draft đồng cảm**, KHÔNG hứa | Tiền + trust + pháp lý. Risk cao nhất. |
| **Auto-send bất kỳ** | GĐ0: `policy_gate` **KHÔNG có nhánh GỬI** — 100% seller duyệt tay (workflow §2.4). Auto-send là evolution `GD1+` sau ≥5000 label + classifier + eval (workflow §8.1) | Core design human-in-loop. Không code path bypass. Nhánh `auto_send` hiện có trong code (opt-in rỗng nên tắt) phải bị **chặn cứng** ở GĐ0 — xem `GD0-POLICY`. |
| **Gate KHÔNG key trên LLM self-report confidence** | Ý định nhạy cảm quyết bằng **rules layer** (keyword/regex + taxonomy §3), KHÔNG bằng `confidence` do LLM tự khai (workflow §2.4) | LLM chấm điểm cao ngay cả khi bịa. `confidence` từ `GD0-DRAFTER` chỉ **advisory**, không phải tín hiệu gate — nguồn gate là `GD0-INTENT`. |

### 2.4 Process
- **ADR bắt buộc** cho: agent orchestration pattern, evaluation strategy, data residency / hosting region.
- **AI-specific PR checklist** cho mọi patch touch `agent/` · `orchestrator` · `policy_gate` · prompt: đã chạy eval? grounding assertion pass? có touch RISK_PATH không? tool param validation?
- **Weekly quality review:** review failed golden case + production sample (sau pilot) + Manual Override Rate theo intent.
- **Dogfooding:** team dùng Ohana trả lời khách thật định kỳ.

### 2.5 Data residency & LLM provider

**Provider = Together AI (open-weight), cả LLM lẫn embedding.** ADR `docs/adr/2026-07-18-hosting-region.md` (**ACCEPTED 2026-07-19**).

- LLM drafting: `meta-llama/Llama-3.3-70B-Instruct-Turbo` (DEC-OHANA-02).
- Embedding: `intfloat/multilingual-e5-large-instruct` (**1024-dim**) thay `text-embedding-3-small` (1536). Cần prefix `query:`/`passage:` — sai bên = retrieval tụt âm thầm.
- **Lý do chiến lược:** open-weight **tách provider khỏi region** — cùng weights chạy Together-US serverless *hoặc* self-host VN, **không phải re-do prompt/eval**. Proprietary API khoá cứng region → không có đường này.

**Pháp lý (verified 2026-07-18; luật sư VN+US phải xác nhận — KHÔNG phải legal advice):**
- **PDPL hiệu lực 1/1/2026** + NĐ 356/2025. Cross-border **không cấm** nhưng buộc **TIA nộp Bộ Công an trong 60 ngày** + thoả thuận bên nhận + consent.
- **Localization:** ngành Luật An ninh mạng (e-commerce/social/payment — **Ohana rơi vào**) có thể buộc lưu data user trên server VN + pháp nhân đại diện VN, *độc lập* với chỗ chạy inference.
- **Chế tài:** tới **5% doanh thu năm trước / 3 tỷ VND**.
- ⚠️ **Không LLM nào "compliant" theo brand.** Chỉ self-host open model TRONG VN mới tránh hẳn trigger cross-border.
- ⚠️ **Đồng hồ 60 ngày chạy từ tin nhắn khách VN THẬT đầu tiên** — tức từ lúc `GD0-ZALO` mount webhook. **Chưa có chủ.**

**Two-data-plane theo tài phán.** Tư cách công ty Mỹ **không miễn** PDPL — luật áp theo **chủ thể dữ liệu**, không theo nơi đăng ký công ty.

| Plane | Chủ thể | Luật | LLM cho phép |
|---|---|---|---|
| **VN** | công dân VN | PDPL + An ninh mạng | DB **tại VN**; inference self-host VN (sạch) *hoặc* hosted + TIA/consent |
| **US** | US persons | state law (CCPA/CPRA) | tự do — Together-US / OpenAI / Anthropic |

🚫 **Anti-pattern:** centralize data VN về DB Mỹ = vượt biên + phá localization.

---

## 3. Intent taxonomy (drives classifier + eval coverage)

Phân theo **cơ chế giải** (cùng câu hỏi, tool khác → risk khác). Input trực tiếp cho `GD0-INTENT` (route) + `GD0-EVAL` (coverage matrix: mỗi loại ≥ N golden case).

| # | Loại (ví dụ thật) | Cơ chế giải | Tool/nguồn | Risk chính | Roadmap ID |
|---|---|---|---|---|---|
| 1 | Còn hàng/size/màu — "còn M ko" | Live lookup, **cấm đoán** | `product_info` | Oversell | `GD0-TOOLS` |
| 2 | Giá — "nhiêu" | Lookup | `product_info` | Sai giá | `GD0-TOOLS` |
| 3 | Discovery/tư vấn chọn — "áo cổ tim", "tôn dáng" | Product RAG + styling | `product_search` + Wiki | Overclaim, hallucinate | `GD2-DISCOVERY` |
| 4 | Size theo dáng — "1m6 50kg mặc gì" | Size-chart logic + body input | `lookup_size` (JSONB, **không RAG** — D9) | Sai size → đổi/trả | `GD0-SHOPS` |
| 5 | Phí ship — "ship Q7 nhiêu" | Parametric — `lookup_shipping` (JSONB `shipping_zones`), carrier API chỉ khi cần giá live | `lookup_shipping` / carrier API | Sai phí | `GD0-SHOPS` / `GD1-SHIP` |
| 6 | Thời gian giao — "bao lâu", "kịp T7?" | Chung: `lookup_shipping` (JSONB) · Cụ thể: tracking | `lookup_shipping` / `order_status` | Hứa sai deadline | `GD0-SHOPS` / `GD1-SHIP` |
| 7 | Chính sách — "COD đc ko", "freeship?" | Text field ráp thẳng system prompt (D7 tầng 3) | `shop_profile` | Thấp (grounded) | `GD0-SHOPS` |
| 8 | Uy tín/sợ scam — "shop real ko" | Text field + tone trấn an (D7 tầng 3) | `shop_profile` | Thấp, nhạy tone | `GD0-SHOPS` |
| 9 | Chốt đơn — "lấy 2 cái" + info | Extraction → draft, **seller duyệt** | order extract | Trích sai đơn | `GD0-FOUNDATION` |
| 10 | Thanh toán — "STK nào", "ck rồi check" | Pay link + **webhook confirm** | payment webhook | Xác nhận TT khống | `GD1-PAY` |
| 11 | Trạng thái đơn — "đơn sao rồi" | Live lookup | `order_status` | Sai trạng thái | `GD0-TOOLS` |
| 12 | Đổi/trả/hàng lỗi | Draft đồng cảm + **escalate**, KHÔNG tự hứa hoàn | Wiki + **human** | **Cao nhất** | `GD0-INTENT` |
| 13 | Khiếu nại/tiêu cực | De-escalate + **low-conf → human** | escalation path | Cao — làm tệ mất khách | `GD0-INTENT` |
| 14 | Sỉ/CTV | Intent route → luồng B2B | classifier route | Thấp | `GD2-DISCOVERY` |
| 15 | Spam/chào/sticker/"." | Classifier → **suppress gợi ý** | intent gate | Phí credit nếu suggest | `GD0-INTENT` |

### 3.1 Ba cơ chế xuyên suốt (quyết định sản phẩm sống/chết)
1. **Hard grounding** (§2.2.10) — nhóm 1,2,5,11 PHẢI từ tool, cấm đoán.
2. **Confidence-gated escalation** (§6.4) — nhóm 12,13 + ngoài catalog + đa nghĩa + tone giận → **không draft**, hiện "cần bạn tự trả lời" + tóm tắt ngữ cảnh. Manual Override Rate cao ở nhóm 12-13 là *đúng thiết kế*.
3. **Multi-intent decomposition** (rất VN) — "còn M ko, ship HN nhiêu, bao lâu?" = 1 tin 3 ý → decompose → N tool → gộp 1 câu. Golden set PHẢI có case đa-intent.

### 3.2 NLU-VN robustness
Khách viết không dấu / lóng / typo ("ship j nhiu", "con ko sh"). Eval phải cover biến thể không dấu + typo, không chỉ câu chuẩn chính tả.

---

## 4. Work items — khoá nối `ROADMAP:` (L1 canonical list)

> Mỗi ID dưới đây là một hàng trong mẫu số. Phase block ở `docs/tasks/` trỏ ngược lên bằng `ROADMAP: <id>`.
> Cột **Class** quyết định mục có vào mẫu số 100% hay không (§0.1). **Không có cột trạng thái — xem L3.**

### 4.1 GĐ0 — MVP Wedge

| ID | Nội dung | Acceptance (đạt mức nào thì xong) | Class | Chờ ai |
|---|---|---|---|---|
| `GD0-BOOTSTRAP` | Repo chạy, fork chọn lọc từ drnickv4, CI + guardrail | `uvicorn app.main:app` chạy; CI xanh; guardrail hook active | internal | — |
| `GD0-MULTITENANT` | `shop_id NOT NULL` mọi bảng; JWT `(user_id, shop_id, role)`; retriever scope SQL-level | Test tenant-isolation: shop A không đọc được row shop B, kể cả qua vector search | internal | — |
| `GD0-CONFIG` | `Settings(BaseSettings)`, embedder wiring env-selecting, secret fail-closed | Fallback dev-only gate trên `OHANA_ENV`; fail-loud ngoài dev | internal | — |
| `GD0-FOUNDATION` | Data model `Customer`/`Conversation`/`OrderDraft` tenant-first; composite FK; test fixture chung | Postgres TỪ CHỐI row shop A trỏ row shop B; `conftest.py` dùng chung | internal | — |
| `GD0-UI` | Seller UI: channel picker, inbox, review card, admin wiki ingest | Seller đăng nhập → duyệt/từ chối reply trong browser thật | internal | — |
| `GD0-CHAT` | General Chat seller↔AI qua Together LLM (KHÔNG tới khách) | Seller gõ trong app → nhận phản hồi thật; gate ranh giới import-graph chặn chat chạm đường gửi khách | internal | — |
| `GD0-EMBED` | Embedder swap OpenAI-1536 → Together e5-1024 + re-embed | `test_wiki_rag_live -m live` PASS trên e5 thật, kiểm **thứ hạng** không chỉ "có trả về" | internal | — |
| `GD0-WIKI` | **Corpus Ohana AI** (tính năng / gói cước / cách dùng / chính sách nền tảng) ingest batch + delta + admin upload. KHÔNG phải corpus của shop — kiến thức shop đi `GD0-SHOPS`, không đi RAG (D7/D8/D9) | Corpus thật ingest; `search_wiki` trả chunk đúng chủ đề | internal | — |
| `GD0-POLICY` | `policy_gate` + orchestrator + `PendingReply` — không code path bypass duyệt. **GĐ0 KHÔNG nhánh GỬI** (workflow §2.4): mọi outcome là PARK hoặc PARK+ESCALATE, seller duyệt tay. Nhánh cổng: sensitive→PARK+ESCALATE (notify riêng) · ngoài window→PARK+mark · chạm cost cap→PARK · còn lại→PARK | Nhánh `auto_send` bị chặn cứng ở GĐ0 (test khẳng định không outcome nào = send); intent nhạy cảm luôn PARK; ESCALATE bắn notify riêng; soak ≥5 decision thật trước SHADOW→hard-block | internal | — |
| `GD0-SHOPS` | `shops` + `shop_profile` (persona text → prompt · knowledge JSONB → lookup) + JWT từ real onboard (không stub) + 2 hàm tra cứu tất định `lookup_size` / `lookup_shipping` | Onboard tạo shop thật → JWT mang `shop_id` thật; `lookup_size(160,50)=="M"` assert được, **không cần LLM-as-judge**; cả hai hàm trả `not_found` tường minh khi thiếu data; phần persona ráp vào prompt ≤ **2000 ký tự** (≈600 token) — cap ở tầng CỘT, không cap từng field rời | internal | — |
| `GD0-HISTORY` | Ghi + đọc `Message` cho conversation (inbound + reply), load last-N vào draft, cap token. **Target last-N = 6 lượt** (workflow §2.3, cứng — không summary GĐ0; summary là evolution §8.2) | Khách hỏi lượt 2 dạng đại từ ("cái đó còn M ko") trả lời đúng; last-N khớp workflow (code hiện `HISTORY_MAX_MESSAGES=20` → **reconcile về 6** hoặc ghi DEC nếu giữ 20); bảng `Message` có đường code ghi vào (`GD0-HISTORY` đã ship phần ghi/đọc) | internal | — |
| `GD0-DRAFTER` | **Implementation thật của `agent.orchestrator.Drafter`** — LLM adapter nhận `(shop_id, customer_id, message, history)` → draft `(text, intent, confidence)`. Ráp `build_persona_prompt` (`GD0-SHOPS`) + last-N history (`GD0-HISTORY`) + tool-calling. Đây là mảnh KHUYẾT giữa "có persona" và "AI Seller nói được": Protocol tồn tại từ spec 01 nhưng **zero implementation**, nên webhook không mount được và persona không có ai tiêu thụ. ⚠️ **Ranh giới với `GD0-INTENT`:** item này chỉ sinh `intent`+`confidence` TỐI THIỂU đủ cho `policy_gate.decide` (từ structured output của chính LLM). Classifier 15 loại + suppress spam + confidence-gated escalation là `GD0-INTENT`, KHÔNG phải ở đây. Ghi ra vì hai item cùng chạm `intent`/`confidence` — đúng kiểu chồng lấn đã khiến `GD0-SHOPS` và spec 03 Phase 1 dẫm chân nhau. | Tin khách qua webhook → draft sinh bằng giọng shop, `intent`+`confidence` đến từ LLM chứ KHÔNG hardcode; draft KHÔNG chứa "Ohana"/"trợ lý ảo"/"tôi là AI" (test regex trên output THẬT, không phải trên prompt); gate import-graph: `Drafter` KHÔNG tự gọi sender — chỉ `orchestrator` quyết gửi hay park. ⚠️ **`confidence` do LLM emit là ADVISORY, KHÔNG phải tín hiệu gate auto-send** (workflow §2.4 cấm gate trên LLM self-report): nguồn quyết định nhạy cảm là rules layer `GD0-INTENT`. Ở GĐ0 mọi draft PARK nên confidence không load-bearing; ràng buộc này chặn việc `GD0-INTENT`/auto-send tương lai vô tình tin số của LLM | internal | — |
| `GD0-METER` | `credit_ledger` tenant-scope + middleware **per-lượt** + per-shop rate limit + **hard cost cap token/ngày/shop** (workflow §5) | Test bypass gọi API trực tiếp vẫn bị trừ credit; rate limit chặn 1 tenant burn cost; **chạm cap ngày → `policy_gate` chuyển mọi tin còn lại trong ngày sang PARK, không gọi LLM** (bảo vệ khỏi spam-bot/config sai) | internal | — |
| `GD0-INGEST` | **Keystone #1 (workflow §7 bước 1) — webhook ACK<2s + queue + DB idempotency.** Tách khỏi `GD0-ZALO`: phần này KHÔNG cần Zalo creds. ACK trước-xử lý sau (worker drain queue), unique constraint `(channel, platform_msg_id)` ở tầng DB (`webhook_event_log`), suy `shop_id` từ `(endpoint, page_id sau verify)` | Webhook trả 200 ≤2s; LLM chạy ở worker không inline; **retry cùng `platform_msg_id` → 200 + KHÔNG enqueue lại** (test 2 webhook đồng thời chỉ 1 row); shop_id không bao giờ từ body chưa verify | internal | — |
| `GD0-DRAFTSCHEMA` | **Keystone #3 (workflow §7 bước 3) — draft schema đúng từ đầu: `TTL` + `snapshot` tầng-1 tại T0 + `label` {approved\|rejected\|edited}.** Schema-shaping, làm khi bảng gần rỗng (đắt sau khi có data) | `PendingReply` có cột snapshot (nguồn/giá trị/thời điểm tầng-1 tại T0) → duyệt lúc T1 so được drift, cảnh báo seller nếu lệch (workflow §2.5); `TTL = min(window platform, ngưỡng shop)`; **mỗi duyệt/từ chối/sửa ghi `label`** nuôi `GD1` auto-send (workflow §8.1) — `edited` phải capture, không gộp vào `status` | internal | — |
| `GD0-COALESCE` | Coalescing debounce cho cả conversation (workflow §2.2, hằng số 4s) — tin xé nhỏ gộp 1 draft | Nhiều tin trong 4s → 1 draft có đủ ngữ cảnh, không sinh N nháp thiếu context; timer reset per-conversation không per-tin | internal | — |
| `GD0-PII` | PII filter trước khi gửi content lên LLM foreign + log destination cho audit (workflow §5). DPIA per-provider + chủ pháp lý đồng hồ-60-ngày là external (§2.5) | Content khách qua filter PII trước mọi call LLM; destination logged; **gate cứng trước khi rời sandbox** (workflow §7 bước 6) | internal | — |
| `GD0-SPLIT` | Luồng A (Ohana AI) và Luồng B (AI Seller) chạy **hai service/process riêng** (workflow §5 — ràng buộc an toàn, không phải sở thích). **Sequencing: pre-prod, KHÔNG chặn critical path GĐ0.** Interim floor = import-graph isolation (đã có, test-enforced) | Hai deployable riêng, crash một bên không kéo bên kia; không có "bộ điều phối rẽ nhánh theo persona" (workflow §5). Cho tới khi split land, gate import-graph là chốt chặn | internal | — |
| `GD0-EVAL` | **Eval harness** — golden fixtures + multi-dim assertion + tool-call/param eval + regression gate CI | Đổi prompt/model/RAG → suite chạy; pass-rate dưới threshold ⇒ **block merge** | internal | — |
| `GD0-ROUTER` | `model_router` plan tier → model id; credit theo model tier (nội bộ) | Orchestrator không còn hardcode model id | internal | — |
| `GD0-INTENT` | Intent classifier 15 loại + suppress spam + **confidence-gated escalation** | Low-conf ⇒ KHÔNG draft, hiện ngữ cảnh cho seller; spam không tốn credit | internal | — |
| `GD0-OBS` | OTel: token/cost/tool-success/RAG-hit/override + trace correlation + p95 gate | 1 trace xuyên conversation ↔ LLM call ↔ tool ↔ external API; p95 < 5s đo trên 100+ msg | internal | — |
| `GD0-RESIDENCY` | Quyết định kiến trúc region + data-flow (ADR) | ADR ACCEPTED + data-flow vẽ ra được | internal | — |
| `GD0-ZALO` | Real `ZaloSender` + **webhook signature verify trên body GỐC** (byte nguyên, trước parse). Idempotency đã tách sang `GD0-INGEST` (internal). Phần này external vì cần Zalo OA creds + signature secret | Gửi/nhận E2E 1 shop thật; signature verify pass trên payload thật; `page_id` chỉ dùng SAU khi chữ ký pass | **external** | Tân (PRE-004) |
| `GD0-TOOLS` | F2 tools `product_info` / `account_lookup` trên endpoint thật. `shipping_info` đã gỡ — phí/thời gian giao chung do `lookup_shipping` (`GD0-SHOPS`) trả, giá live carrier là `GD1-SHIP` | 2 tool gọi platform API thật, param validation trước execute | **external** | Tân (PRE-002) |
| `GD0-WINDOW` | Zalo 48h reactive window scheduler + cảnh báo seller | Seller được cảnh báo trước khi window đóng | **external** | Tân (PRE-004) |

#### 4.1.1 Derivation map — `derives_from` (ADR 2026-07-22)

> Khoá nối tầng-trên: mỗi ID neo vào một anchor trong [`backend-workflow.md`](backend-workflow.md).
> Máy đọc block này (`verify_derives`); dangling anchor ⇒ block commit.
> `# weak-mapping` = map tạm, remap khi workflow tách sâu hơn. `n/a (scaffold)` = miễn theo ADR §5.1.

| ID | `derives_from` | Ghi chú |
|---|---|---|
| `GD0-INGEST` | `workflow#w-7.1-webhook` | |
| `GD0-INTENT` | `workflow#w-7.3-rules-intent` | |
| `GD0-DRAFTSCHEMA` | `workflow#w-7.4-draftschema` | |
| `GD0-SHOPS` | `workflow#w-7.5-shop-profile` | |
| `GD0-DRAFTER` | `workflow#w-7.7-draft-pipeline` | |
| `GD0-HISTORY` | `workflow#w-7.7-draft-pipeline` | |
| `GD0-POLICY` | `workflow#w-7.7-draft-pipeline` | |
| `GD0-PII` | `workflow#w-7.2-pii-filter` | anchor cũ `w-7.6-pii-dpia` bị TÁCH đôi; nửa DPIA ở `w-7.8-dpia` (external, §2.5) |
| `GD0-WIKI` | `workflow#w-7.9-corpus-luong-a` | |
| `GD0-EMBED` | `workflow#w-7.9-corpus-luong-a` | |
| `GD0-CHAT` | `workflow#w-7.9-corpus-luong-a` | |
| `GD0-METER` | `workflow#w-7.6-cost-cap` | ✅ hết weak — §7.6 có step cost-cap pre-charge riêng |
| `GD0-ZALO` | `workflow#w-7.1-webhook` | `# weak-mapping` — signature/sender là §2.1, §7.1 nhấn idempotency |
| `GD0-COALESCE` | `workflow#w-7.1-webhook` | `# weak-mapping` — debounce §2.2, §7 chưa có step riêng |
| `GD0-TOOLS` | `workflow#w-7.7-draft-pipeline` | `# weak-mapping` — WHY thật ở §3 tầng-1 |
| `GD0-WINDOW` | `workflow#w-7.1-webhook` | `# weak-mapping` — 48h window chưa có anchor riêng |
| `GD0-SPLIT` | `workflow#w-5-boundary` | |
| `GD0-RESIDENCY` | `workflow#w-5-boundary` | |
| `GD0-MULTITENANT` | `workflow#w-5-boundary` | |
| `GD0-FOUNDATION` | `workflow#w-3-data-tiers` | |
| `GD0-EVAL` | `workflow#w-9-ai-eng` | ⚠️ §9 còn placeholder — WHY chưa viết |
| `GD0-ROUTER` | `workflow#w-9-ai-eng` | ⚠️ §9 còn placeholder |
| `GD0-OBS` | `workflow#w-9-ai-eng` | ⚠️ §9 còn placeholder |
| `GD0-BOOTSTRAP` | `n/a (scaffold)` | miễn theo ADR §5.1 |
| `GD0-CONFIG` | `n/a (scaffold)` | miễn theo ADR §5.1 |
| `GD0-UI` | `n/a (scaffold)` | miễn theo ADR §5.1 |

*GĐ1–GĐ3 (§4.2–4.4) chưa map: `backend-workflow.md` hiện chỉ mô tả GĐ0.*

**Gate GĐ0 acceptance:** E2E shop thật + eval pass + metering + escalation + p95. Pilot 3–5 shop.

### 4.2 GĐ1 — Payment + Fulfillment

| ID | Nội dung | Acceptance | Class | Chờ ai |
|---|---|---|---|---|
| `GD1-STATE` | Order state machine (`draft→paid→shipped→delivered→refunded`) + **transition audit log** + webhook idempotency | Mọi transition có audit entry; retry webhook dedup theo key | internal | — |
| `GD1-PAY` | Payment link thật (VietQR **hoặc** MoMo) + webhook xác nhận → tự chuyển state | 1 giao dịch thật tự chuyển state, không thao tác tay | **external** | provider onboarding |
| `GD1-SHIP` | 1 hãng (GHTK **hoặc** GHN): tạo vận đơn, tracking, webhook | Vận đơn thật + ≥3 trạng thái webhook (created/picked/delivered) | **external** | carrier onboarding |
| `GD1-COD` | COD reconciliation script 1 hãng | `net = COD − phí ship − phí COD` khớp **raw carrier export**, không tự sinh test data | **external** | ≥5 đơn COD thật |

**Rủi ro giấu:** rounding drift COD; state machine phải có bảng transition tường minh (compliance + debug).
**Tái dụng:** `bridge/ohana_client.py` pattern (verify=True) → `payment_client.py` + `shipping_client.py`. ROI cao.

### 4.3 GĐ2 — Đa kênh + Đối soát + Analytics + Discovery

| ID | Nội dung | Acceptance | Class | Chờ ai |
|---|---|---|---|---|
| `GD2-CHANNEL` | Channel abstraction (`channels/base.py` Protocol + Zalo migrate) | Port kênh 2 **không sửa core** — đó là bằng chứng abstraction đúng | internal | — |
| `GD2-MESSENGER` | FB Messenger channel implement | 2 kênh chạy song song qua 1 abstraction | **external** | Meta App Review 4-8 tuần, **có thể reject** |
| `GD2-CARRIER` | Multi-carrier shipping (hãng #2 + fee policy config) | Hãng #2 chạy không sửa core shipping | internal | — |
| `GD2-RECONCILE` | COD reconcile đa hãng + generic engine + script parity test | Khớp **100%** trên raw carrier export CSV đa hãng | internal | — |
| `GD2-ANALYTICS` | Analytics Pro — script trước, dashboard sau | Reconciliation script pass ≥30 ngày data thật | internal | — |
| `GD2-DISCOVERY` | Semantic product discovery (VLM enrich + facet taxonomy + `product_search`) | Query NL → top-k grounded, facet đúng, **không overclaim** + human review sample | internal | — |

**Quyết định đã chốt:** discovery dùng **VLM enrich-at-ingest (approach A)**, KHÔNG cross-modal CLIP — lý do §6.5. Reconcile **KHÔNG generic sớm**: làm 1 hãng (GĐ1) thấy quirk rồi mới extract engine ở GĐ2; không biết abstraction đúng khi chưa thấy 2 hãng.

### 4.4 GĐ3 — Billing + Reseller + Hardening

| ID | Nội dung | Acceptance | Class | Chờ ai |
|---|---|---|---|---|
| `GD3-RECURRING` | Recurring payment provider eval + integration | Charge chạy ≥1 chu kỳ thật (charge + retry + failure notification) | **external** | provider |
| `GD3-BILLING` | Subscription (tier + credit chu kỳ + model tier gate + up/downgrade) | Plan tier gate model đúng qua `GD0-ROUTER` | internal | — |
| `GD3-RESELLER` | Reseller model — **single-level flat** (ràng buộc kỹ thuật, agent không tự sinh nested) | Cấp/thu hồi license + tier đúng, verify ≥3 reseller thật | internal | — |
| `GD3-HARDEN` | Rate-limit mở rộng + monitoring + backup + log retention + **worker isolation** | Background job scoped theo shop | internal | — |
| `GD3-SOAK` | Multi-tenant soak + JWT fuzz + query-planner audit + load test | Load target **N = 3× shop pilot cuối GĐ2** | internal | — |
| `GD3-AUDIT` | External security review (audit firm) | PASS — không HIGH severity finding open | **external** | audit firm |

---

## 5. Dependency graph

```
GD0-BOOTSTRAP → GD0-MULTITENANT → GD0-CONFIG → GD0-FOUNDATION → GD0-UI → GD0-CHAT
GD0-EMBED → GD0-WIKI  ── không chờ ai; corpus Ohana AI do Wyatt + Anh Sơn viết, KHÔNG dính Tân
GD0-EVAL           ── không chờ ai; là PREREQUISITE của GD0-INTENT **VÀ** thay-đổi-prompt
                     kế tiếp trong GD0-DRAFTER (rule §4: "đổi prompt/model/RAG → suite
                     chạy; pass-rate < threshold ⇒ block merge" cover MỌI prompt change).
                     Spec 07/11/13 (chat/persona/Drafter) đã ship prompt TRƯỚC khi eval
                     land — waiver ngầm: chấp nhận silent-wrong risk cho 3 prompt hiện
                     có, gate CỨNG cho spec Drafter mở rộng tiếp. Reconciled 2026-07-24.
GD0-SHOPS / HISTORY / METER / ROUTER / OBS / RESIDENCY  ── không chờ ai
GD0-INGEST (webhook ACK+queue+idempotency) ── keystone #1 workflow §7; INTERNAL, không chờ ai
GD0-DRAFTSCHEMA (TTL+snapshot+label)       ── keystone #3 workflow §7; schema TRƯỚC khi có data
GD0-COALESCE / GD0-PII / GD0-SPLIT         ── internal (SPLIT sequencing pre-prod, không chặn)
GD0-SHOPS ─┐
GD0-HISTORY┼→ GD0-DRAFTER ── không chờ ai; là thứ BIẾN persona + history thành câu trả lời
GD0-CHAT  ─┘     (TogetherClient tái dùng từ GD0-CHAT — cùng LLM client, khác đường ra)
GD0-EVAL  ─┘     ── spec Drafter MỞ RỘNG (post-spec-13) phải BLOCKED_BY: GD0-EVAL
      └─ mount api/webhook.py cần: GD0-INGEST (ACK+idem, internal) + GD0-DRAFTER (impl)
         + GD0-ZALO (signature+sender, PRE-004 kẹt Tân)
         ⇒ GD0-INGEST gỡ được NGAY (không chờ Tân); chỉ signature-verify kẹt PRE-004

⛔ GD0-ZALO / TOOLS / WINDOW  ── kẹt PRE-002/004 ở Tân (idempotency đã tách sang GD0-INGEST internal)
      └─ [Gate GĐ0 acceptance]
            └─ Meta App Review submit NGAY (chuẩn bị GĐ2 — lead time 4-8 tuần)

GD1-STATE → GD1-PAY / GD1-SHIP → GD1-COD      └─ [Gate GĐ1]
GD2-CHANNEL → GD2-MESSENGER ; GD2-CARRIER → GD2-RECONCILE → GD2-ANALYTICS ; GD2-DISCOVERY (song song)
                                               └─ [Gate GĐ2]
GD3-RECURRING → GD3-BILLING → GD3-RESELLER ; GD3-HARDEN → GD3-SOAK → GD3-AUDIT
                                               └─ [Gate GĐ3]
```

**Critical path GĐ0→GĐ3:** ~24-35 tuần (~6-8 tháng), không tính lead-time Meta/provider/audit firm.

---

## 6. AI engineering — chi tiết

### 6.1 Eval harness (`GD0-EVAL`)
**Vấn đề:** đo latency nhưng không đo reply tốt không. Prompt/model change có thể âm thầm làm reply tệ mà không test nào bắt.

**Multi-dimensional eval:**
- **Structural** (deterministic): không markdown/`**`, độ dài 1-3 câu, không lộ system prompt, đúng ngôn ngữ VN.
- **Grounding/Faithfulness**: không bịa giá/policy/size ngoài Wiki+catalog. Hallucination guard cốt lõi.
- **Action correctness**: gọi ĐÚNG tool + ĐÚNG param, **param validation trước execute** (qty/price sanity, bound check).
- **Tone/Voice**: đúng giọng người bán VN, không cứng/tây.
- **Safety compliance**: không vi phạm guardrail §2.3.

**Kết hợp:** rule-based (structural/grounding) + LLM-as-Judge (tone) + **Manual Override Rate** (ground-truth free từ pilot).

**Golden set:** **KHÔNG synthetic 200 conv** (làm yếu grounding eval). Bắt đầu nhỏ từ conv pilot thật + hard case (nhóm 12-13 + đa-intent + không dấu), nuôi lên. Coverage: mỗi intent family (§3) ≥ N case.

**Online eval:** land **hook** sampling production conv nhưng **chạy sau pilot**. Không phải GĐ0.

### 6.2 Model routing (`GD0-ROUTER`)
`agent/model_router.py`: `plan_tier → model_id`. Credit tính cost theo model tier (nội bộ, để margin); seller-facing vẫn per-lượt.
**KHÔNG dynamic complexity routing** giai đoạn này — tối ưu con số chưa đo, và classify complexity tốn thêm latency/call mỗi tin.

### 6.3 LLM observability (`GD0-OBS`)
Span quanh `orchestrator.step`: `token_in/out`, `cost`, `model_id`, `tool_calls[]` (+success/fail), `rag_hit`, `fallback_triggered`, `latency_ms`, `override`. **Trace correlation** 1 trace xuyên suốt. **Cost attribution per shop/plan.** Anomaly detection **defer** cho tới khi có baseline.

### 6.4 Confidence-gated escalation (`GD0-INTENT`)
**Failure mode chết người:** AI **tự tin** draft câu SAI → seller bấm duyệt cho nhanh → thảm hoạ. Giải KHÔNG phải "AI giỏi hơn" mà là **AI biết lúc nào KHÔNG nên gợi ý**.

Trigger → không draft, hiện "cần bạn tự trả lời" + tóm tắt ngữ cảnh: query ngoài catalog/Wiki · tranh chấp/hoàn tiền (nhóm 12) · tone giận (nhóm 13) · đa nghĩa cao.

Manual Override Rate cao ở các nhóm này = **đúng thiết kế**, không phải bug.

### 6.5 Semantic product discovery (`GD2-DISCOVERY`)
Kỹ thuật: **VLM catalog enrichment + semantic retrieval** — *enrich-at-ingest → index → retrieve*.

**Chỗ khó thật nằm ở data design, không ở AI:**
1. **Taxonomy là phần khó nhất.** Hybrid: **facet kiểm soát** (cổ: tròn/tim/vuông/thuyền · dáng: ôm/suông/oversize/peplum · dịp) cho *hard-filter* + **1 blob mô tả** cho *semantic recall*. Filter facet rồi rank vector trong đó — chính xác hơn vector thuần (vector thuần dễ trả "váy đỏ nhưng sai cổ").
2. **Hallucination lúc enrich = độc** (vừa retrieve sai vừa tư vấn sai gửi khách). Mitigate: extraction **schema-constrained + vocab kiểm soát**, sample human review, **cấm overclaim** ("tôn dáng"/"giảm 5kg" chạm consumer-trust).
3. **Advisory query cần knowledge layer.** "Tôn dáng cho người tròn" = kiến thức styling, không phải data SP.
4. **Ảnh seller messy** → chọn ảnh nào enrich (ưu tiên ảnh mặc trên người).
5. **Re-enrichment + cost:** cache theo image-hash; batch khi 10k+ SP.

**Unverified:** chưa đọc import/`parsing/` pipeline thật — fit ở trên mới suy từ roadmap.

---

## 7. GĐ4 — Financial AI (ngoài scope, không vào mẫu số)

**Cảnh báo bắt buộc trước khi start:**
1. **Eval/safety framework riêng.** Priority order hiện tại không đủ cho crypto/BĐS/CK/vàng — reactivate framework kiểu ONFA (LR/WP/TV/UR).
2. **Spec-generator branch riêng** — không tái dụng template GĐ0-3.
3. **Kiến trúc khác bản chất:** Ohana = advisor, **không hold funds**. Regulatory constraint từng asset class ảnh hưởng data model + hosting + audit trail — không port thẳng ONFA fintech code.

---

## 8. Cross-cutting risks

| Risk | Impact | Mitigation | ID liên quan |
|---|---|---|---|
| **Multi-tenant data leak** | HIGH — mất trust vĩnh viễn | `shop_id` SQL-level; reviewer check patch touch `retrieval/*`/`db/*`; soak + query-planner audit | `GD0-MULTITENANT`, `GD3-SOAK` |
| **Policy gate bypass** | HIGH — reply sai tới khách | `policy_gate` cứng; SHADOW → hard-block sau ≥5 real decision | `GD0-POLICY` |
| **AI overconfident sai** | HIGH — thảm hoạ im lặng | Confidence-gated escalation — không draft khi low-conf | `GD0-INTENT` |
| **AI regression** | HIGH — reply tệ silent | Eval regression gate; không đổi prompt/model/RAG mà không chạy suite | `GD0-EVAL` |
| **Fact hallucination** | HIGH — oversell, hứa sai | Hard grounding: fact → tool, cấm đoán | `GD0-TOOLS` |
| **Tool hallucination** | HIGH — hành động sai | Action-correctness eval + param validation trước execute | `GD0-EVAL` |
| **Enrichment overclaim** | HIGH — consumer trust | Schema-constrained + cấm overclaim + human sample + seller duyệt | `GD2-DISCOVERY` |
| **Payment confirm bằng lời khách** | HIGH — giao đơn chưa trả | Chỉ payment webhook xác nhận | `GD1-PAY` |
| **Prompt injection** | HIGH — tool ngoài scope | Input-side hardening + tool-call qua cùng authorization | `GD0-POLICY` |
| **AI freelance discount** | MEDIUM — mất margin | Rule bounded hoặc human | `GD0-POLICY` |
| **LLM cost blowout** | MEDIUM — burn | Credit metering + per-shop rate limit + cost-per-conv alert | `GD0-METER` |
| **LLM provider outage** | MEDIUM — seller kẹt | Heuristic fallback + SLO. Multi-provider chỉ nếu uptime data chứng minh | `GD0-CHAT` |
| **Financial rounding drift** | MEDIUM — mất trust seller | Reconciliation parity raw carrier CSV | `GD1-COD`, `GD2-RECONCILE` |
| **Data residency** | HIGH — kiến trúc | Region + data-flow trước GĐ0 ship | `GD0-RESIDENCY` |
| **Webhook gửi trùng** (không idempotent) | HIGH — khách nhận 2 tin / draft đôi | ACK-then-process + unique `(channel, platform_msg_id)` tầng DB (workflow §2.1) | `GD0-INGEST` |
| **Duyệt trên dữ kiện cũ** (không snapshot) | MEDIUM — oversell/hứa sai lúc T1 | Snapshot tầng-1 tại T0 + drift-check lúc duyệt (workflow §2.3/2.5) | `GD0-DRAFTSCHEMA` |
| **Không ghi label từ đầu** | MEDIUM — auto-send GĐ1 phải tích data lại từ đầu | `label` {approved/rejected/edited} ghi mỗi lượt duyệt (workflow §8.1) | `GD0-DRAFTSCHEMA` |
| **Luồng A bịa rò sang khách Luồng B** | HIGH — persona lộ / nội dung sai tới khách | Hai service riêng + không bộ điều phối rẽ nhánh (workflow §5); interim = import-graph isolation | `GD0-SPLIT` |
| **PII xuyên biên giới lên LLM** | HIGH — PDPL/NĐ13, chế tài 5% doanh thu | Filter PII trước gửi LLM + destination log + DPIA (workflow §5) | `GD0-PII` |
| **Meta App Review delay/reject** | MEDIUM — chặn GĐ2 | Submit cuối GĐ0. Kế hoạch B: mở rộng Zalo-only | `GD2-MESSENGER` |
| **RISK tier drift** | HIGH — silent gate bypass | ADP hook floor: `files ∩ RISK_PATHS ≠ ∅ ⇒ ≥ medium` | — |
| **Spec drift** | HIGH — mất change-control | `adp_spec_lock_verify` chặn checkpoint | — |
| **Roadmap drift** (L1 và L2 rời nhau) | HIGH — kế hoạch thành hư cấu | L3 `uncovered` + `unplanned` phát hiện hai chiều | — |

---

## 9. Change log

| Date | Change | Author |
|---|---|---|
| 2026-07-21 (v6) | **Adopt [`backend-workflow.md`](backend-workflow.md) làm cấu trúc code CHÍNH THỨC (DEC-OHANA-05).** Workflow thắng khi lệch L1. Hoà giải 6 điểm lệch (append-only, không rename/xoá ID, không đụng code/L2): (1) cấm nhánh `auto_send` GĐ0 + gate KHÔNG key LLM confidence → siết `GD0-POLICY`/`GD0-DRAFTER` + §2.3; (2) tách idempotency internal khỏi `GD0-ZALO` → **thêm `GD0-INGEST`** (keystone #1, làm ngay không chờ Tân); (3) **thêm `GD0-DRAFTSCHEMA`** (TTL+snapshot+label, keystone #3); (4) **thêm `GD0-SPLIT`** two-service (sequencing pre-prod, interim=import-isolation); (5) **thêm `GD0-PII`** filter+DPIA; (6) **thêm `GD0-COALESCE`** debounce 4s. Siết `GD0-METER` (hard cost cap→PARK), `GD0-HISTORY` (last-N=6). Mẫu số `internal` GĐ0 **tăng** (+5 item) — % giảm là honest (§0.2: thêm không phải gian lận, khác xoá). §5 graph + §8 risks cập nhật. Copy workflow doc vào repo `docs/backend-workflow.md`. | Claude (main loop) |
| 2026-07-19 (v5) | **Roadmap vào ADP làm xương sống (DEC-OHANA-03).** Tách 3 tầng L1/L2/L3: file này thành tầng **ý định thuần, bỏ hết STATUS**; thêm **ID bền** cho 35 work item + cột **Class** (internal/external/out-of-scope) để mẫu số 100% có nghĩa; khoá nối `ROADMAP:` vào phase block; L3 `ROADMAP-STATUS.md` sinh máy. Hợp nhất 4 tài liệu lộ trình đang mâu thuẫn → 1 nguồn: bản v3 hoá thạch trong repo + 2 file PLAN companion đưa vào `docs/archive/`. Bổ sung §2.1.5 SMOKE gate. Ghi nhận `GD0-CHAT` shipped, ADR PRE-007 ACCEPTED, `GD2-CHANNEL` đã kéo sớm về spec 06. | Claude (main loop) |
| 2026-07-18 (v4) | Re-prioritize: ship General Chat trước (chỉ cần Together key). Provider chốt = Together AI open-weight cho cả LLM + embedding (e5-1024 thay OpenAI-1536). §2.5 data residency: PDPL + TIA 60 ngày + localization + two-data-plane VN/US. | Claude (main loop) |
| 2026-07-17 (v3) | Intent taxonomy 15 loại; guardrails §2.3; confidence-gated escalation first-class; hard grounding; Manual Override Rate; product discovery approach A. Reject (premature): framework migration, multi-agent, fine-tuning, dynamic routing, guard model, generic reconcile sớm, token-based metering, multi-provider sớm. | Claude (main loop) |
| 2026-07-17 (v2) | Rebuild thuần tech: cắt tranche/rev-share/legal-process. Bơm AI-eng spine. | Claude (main loop) |
| 2026-07-17 (v1) | Initial draft. | Claude (main loop) |

---

*L1 = ý định. Execution vẫn phải qua `docs/tasks/NN-Task-*.md` với ADP phase block + checkpoint. Trạng thái đọc ở [`ROADMAP-STATUS.md`](ROADMAP-STATUS.md).*
