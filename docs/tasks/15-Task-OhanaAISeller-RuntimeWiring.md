# 15-Task-OhanaAISeller-RuntimeWiring

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-22 "gộp dọn loại-2 + verify Tool-shape vào spec 15") -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng trục safety→trust→stability→growth, -->
<!-- KHÔNG dùng Survival Framework LR/WP/TV/UR — Ohana không có cột tài chính. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ráp tiểu-hệ-thống outbound (de-orphan LLMDrafter + tool set) + dọn dead code loại-2 + verify Tool-shape |
| Parent | `GD0-DRAFTER` (impl DONE spec 13) + `GD0-INGEST` (schema DONE spec 14) — L1 `docs/ROADMAP.md` §4.1 |
| Structural source | [`docs/backend-workflow.md`](../backend-workflow.md) §2.3 (bộ soạn nháp), §5 (ranh giới), §7 bước 5 |
| Depends-on | Spec 11 (Shops/tools, DONE) · Spec 13 (LLMDrafter, DONE) · Spec 14 (schema, DONE) |
| Unblocks | `GD0-ZALO` (chỉ còn signature-verify + live mount) · snapshot capture + worker drain (runtime còn lại của ISSUE-026) |
| Owner | R: Claude · A: Wyatt |
| Branch | `adp/15-Task-OhanaAISeller-RuntimeWiring` (đã tạo 2026-07-22, base `4affc6a`) |
| Spec type | Wiring + Cleanup · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

### 1.1 Audit 2026-07-22: một tiểu-hệ-thống outbound nguyên khối bị ngắt kết nối

Import-graph audit (HEAD `4affc6a`) tìm ra **không có luồng song song phân kỳ** (bản `_Drafter` Protocol trùng lặp đã bị xoá có chủ ý, `api/webhook.py:33`), nhưng lộ một cụm **mồ côi** chia hai loại:

**Loại 1 — "chờ nối" (built spec 13/14, spec này tiêu thụ):**
1. `agent/drafter.py::LLMDrafter` — impl thật (spec 13). **0 prod importer** — chỉ test dựng. `LLMDrafter.__init__(tools=())` nhận tool qua DI, default RỖNG ⇒ điểm nối sẵn, chưa ai gọi.
2. `tools/shop_kb.py::build_size_tool/build_shipping_tool` + `tools/ohana_read.py::build_order_status_tool` — factory trả đúng `Tool` dataclass. **0 prod importer.** Chưa ai ráp thành tool set inject.
3. `api/webhook.py::build_router(drafter, …)` — factory SẴN, nhận `Drafter` + gọi `receive_and_draft`. **Không mount** (`app/main.py` không `include_router`).

**Loại 2 — rác thật (không spec nào định tiêu thụ):**
4. `storage/base.py` + `storage/local.py` — **0 reference** trong toàn prod (chỉ test). Fork residue từ `drnickv4/`, port dư.
5. `tools/registry.py::register()` + global `TOOLS: dict` — `register()` **không ai gọi**. Cơ chế đăng-ký-global (thiết kế gốc, docstring "Phase 3 lands the shape") bị **constructor DI** của spec 13 thay thế ⇒ dead.
6. Comment `app/main.py:16-19` **và** `api/webhook.py:8` cùng nói *"no concrete Drafter implementation yet"* — **SAI**: spec 13 đã thêm `LLMDrafter`. Đúng loại landmine repo tự cảnh báo (ISSUE-024 "Protocol nói dối").

### 1.2 Hệ quả nếu để nguyên

- **LLMDrafter + tools mồ côi mãi** ⇒ persona (spec 11) + history (spec 10) + drafter (spec 13) có đủ nhưng **không đường nào biến thành câu trả lời**. Đây là mắt xích khuyết giữa "có mảnh" và "AI Seller nói được".
- **Hai cơ chế tool song song** (`register()` global vs DI) ⇒ khi nối, người sau phân vân đường nào ⇒ đúng chỗ scope trôi. Phải chọn một, xoá một, **trước** khi ráp.
- **Comment nói dối** ⇒ người đọc `main.py`/`webhook.py` tin Drafter chưa tồn tại ⇒ có thể viết lại throwaway glue (đúng thứ ISSUE-024 gây ra).
- **`storage/*` mồ côi** ⇒ mypy/ruff vẫn quét, review vẫn phải đọc, nợ đọc-hiểu không lý do.

### 1.3 ⚠️ Ranh giới CỨNG: ráp + test nội bộ, KHÔNG mở đường ra khách

`api/webhook.py` là **biên giới tin khách vào**. Mount live nó = (a) cần signature-verify + Zalo creds (`GD0-ZALO`, PRE-004, **kẹt Tân**), và (b) **khởi động đồng hồ PDPL 60 ngày** (L1 §2.5) — thứ **chưa có chủ legal**. Vì vậy spec này ráp toàn bộ chuỗi và chứng minh bằng integration test dùng `MockZaloSender`, **KHÔNG `include_router` webhook live**. De-orphan bằng cách *dựng + test*, không bằng cách *mở cửa*. Một dòng `include_router` cách live — nhưng dòng đó thuộc `GD0-ZALO`, sau khi PRE-004 sạch + có chủ PDPL.

---

## §2 — Goal

**VI:** `LLMDrafter` được dựng thật trong `app/main.py` với tool set ráp từ `shop_kb`/`ohana_read` (đã verify khớp `Tool` + không rò `user_id`/`shop_id` vào `parameters`); chuỗi inbound→drafter→`policy_gate`→`PendingReply` chứng minh chạy đúng end-to-end bằng integration test với `MockZaloSender` (nhánh park). Dead code loại-2 (`storage/*`, `register()`/`TOOLS`) bị xoá; hai comment "no Drafter yet" sửa đúng. **Webhook KHÔNG mount live** — zero tin khách rời máy, đồng hồ PDPL KHÔNG chạy. Zero đổi hành vi của `chat`/`inbox`/`admin` hiện có.

**EN:** `LLMDrafter` is really constructed in `app/main.py` with a tool set assembled from `shop_kb`/`ohana_read` (verified to match `Tool` and to not leak `user_id`/`shop_id` into `parameters`); the inbound→drafter→`policy_gate`→`PendingReply` chain is proven end-to-end by an integration test using `MockZaloSender` (park branch). Loại-2 dead code (`storage/*`, `register()`/`TOOLS`) is deleted; both stale "no Drafter yet" comments fixed. The webhook is NOT live-mounted — no customer message leaves the machine, the PDPL clock does not start. No behavior change to existing `chat`/`inbox`/`admin`.

---

## §3 — Scope

- `app/main.py` — dựng `LLMDrafter` + ráp `webhook.build_router(drafter, …)` (KHÔNG `include_router`, hoặc dev-gate — xem Q1); sửa comment cũ.
- `api/webhook.py` — sửa comment `:8` cũ (KHÔNG đổi logic; router factory giữ nguyên).
- `tools/registry.py` — xoá `register()` + `TOOLS` (sau khi PRE-1502 xác nhận 0 reader); GIỮ `Tool` dataclass. Thêm `build_grounding_tools(...)` (xem Q3).
- `tools/wiring.py` (mới, tuỳ Q3) hoặc trong `registry.py` — factory ráp tool set.
- Xoá `storage/base.py`, `storage/local.py`, `storage/__init__.py` (sau PRE-1501).
- `tests/test_runtime_wiring.py` (mới) — tool-shape assert + integration chain.
- `docs/memory/KNOWN_ISSUES.md` (ISSUE-026 đóng phần đã nối, ghi rõ phần còn hoãn) · `docs/ROADMAP.md` (đóng vòng L3).

### Out of scope (cố ý — runtime còn lại / external)

- ❌ **`include_router(webhook)` live** — `GD0-ZALO`, cần signature-verify (PRE-004) + chủ PDPL. Đây là ranh giới §1.3.
- ❌ **Signature-verify + Real `ZaloSender`** — `GD0-ZALO`, PRE-004 kẹt Tân. Test dùng `MockZaloSender`.
- ❌ **Snapshot CAPTURE lúc draft** (`agent/orchestrator.py` ghi cột `snapshot` spec 14) — đổi hành vi draft, concern riêng; cột nullable chờ sẵn.
- ❌ **TTL compute + cron expiry** (`expires_at`) · **worker drain `approved`→sender** — runtime còn lại ISSUE-026.
- ❌ **Wire `record_event` idempotency vào webhook** — thuộc webhook path (mount = out of scope).
- ❌ **Đổi `HISTORY_MAX_MESSAGES` 20→6** — reconcile riêng (workflow-adoption follow-up).

---

## §4 — Safety Gate Check (trục Ohana: safety → trust → stability → growth)

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Webhook KHÔNG mount ⇒ **không đường vật lý nào** đưa draft tới khách; đồng hồ PDPL không chạy. Tool set inject qua DI phải giữ bất biến R1.1: `parameters` KHÔNG chứa `user_id`/`shop_id` — orchestrator cấp từ verified `Identity`, LLM không chỉ tool sang shop khác. P2 test đúng cái đó. `policy_gate` KHÔNG đổi — mọi draft vẫn park/escalate, không nhánh gửi. | PASS (điều kiện: webhook không mount — Q1) |
| **User trust** | Nối drafter = bước để AI Seller trả lời có căn cứ (grounding tool). Nhưng chưa tới khách trong spec này ⇒ rủi ro trust = 0 bây giờ, giá trị hiện khi `GD0-ZALO` mount. | PASS |
| **Stability** | Xoá dead code (`storage/*`, `register()`): nếu full suite xanh sau khi xoá = **chứng minh nó chết**. Dựng LLMDrafter trong main.py không đổi router đang mount (chat/inbox/admin) — integration test riêng chuỗi mới. | PASS (điều kiện: PRE-1501/1502 xác nhận 0 reader) |
| **Growth** | Sau spec này `GD0-ZALO` chỉ còn signature-verify + 1 dòng mount — mọi mảnh đã ráp + test. | PASS |

**RED FLAG scan:**

- [x] **Xoá `storage/*` + `register()` PHẢI có PRE xác nhận 0 reader trước.** Audit grep=0 nhưng grep base-name nhiễu — PRE-1501/1502 chạy grep chính xác lúc execute, KHÔNG tin số audit. Xoá nhầm cái đang dùng ⇒ import error lúc boot.
- [x] **`build_grounding_tools` KHÔNG được để LLM thấy `user_id`/`shop_id`.** Bất biến R1.1: hai field đó là tham số handler `(user_id, shop_id, args)`, KHÔNG bao giờ trong `Tool.parameters`. P2 assert cơ học trên mọi tool ráp vào.
- [x] **Integration test P3 chạy nhánh PARK, KHÔNG send.** `MockZaloSender` + intent thường ⇒ `policy_gate` park ⇒ `PendingReply` row. KHÔNG test "auto-send" (không tồn tại). Nếu test gọi `sender.send()` = sai thiết kế.
- [x] **Dựng LLMDrafter cần LLM client — dùng LẠI `TogetherClient` của `GD0-CHAT`, KHÔNG tạo provider path thứ hai.** Cùng client, khác đường ra (L1 §5 dependency graph). Tạo client mới = luồng song song mới, đúng thứ audit này đi tìm.
- [ ] ⚠️ **Nếu Q1 chọn dev-gate mount thay vì unmounted:** signature-verify phải fail-CLOSED ngoài `OHANA_ENV=="dev"` (CLAUDE.md §3 dev-fallback). Mount dev-gate vẫn là đường khách-vào ở dev ⇒ cân nhắc PDPL kể cả dev nếu có tin thật. Đề xuất mặc định = **unmounted** cho tới `GD0-ZALO`.

---

## §5 — Source files

Đọc TRƯỚC khi sửa: `agent/drafter.py` (`LLMDrafter.__init__` — DI tools, cách nó gọi tool-loop + `emit_reply`) · `agent/orchestrator.py` (`receive_and_draft`, `Drafter` Protocol, chỗ inject drafter) · `api/webhook.py` (`build_router(drafter, …)` §48+ — factory sẵn, comment cũ `:8`) · `app/main.py` (pattern `build_*_router` + `include_router`, comment cũ `:16-19`, cách dựng dep cho `chat` để tái dùng LLM client) · `api/chat.py` (cách `GD0-CHAT` dựng `TogetherClient` — tái dùng, KHÔNG nhân bản) · `tools/registry.py` (`Tool` dataclass giữ, `register()`/`TOOLS` xoá) · `tools/shop_kb.py` + `tools/ohana_read.py` (`build_*_tool` factories — shape để verify + ráp) · `bridge/zalo_sender.py` (`MockZaloSender` cho integration test) · `storage/__init__.py` (xác nhận chỉ docstring, xoá) · `docs/backend-workflow.md` §2.3/§5.

---

## §6 — PRE checks

```
PRE-1501: storage/* thật sự 0 reader? (xoá dead)
  Trạng thái: ⏳ ĐO lúc execute. Audit grep=0 nhưng nhiễu base-name.
  Command: grep -rn "from storage\|import storage\|LocalStorage\|storage\.base\|storage\.local" \
           --include='*.py' app agent api parsing bridge auth db tools app/main.py | grep -v ".venv"
  Pass: rỗng ⇒ xoá an toàn. Có hit ⇒ hit đó là reader thật, KHÔNG xoá, báo Wyatt.

PRE-1502: tools/registry.py::register() + TOOLS global 0 reader?
  Trạng thái: ⏳ ĐO. Audit: register( không ai gọi; nhưng TOOLS dict có thể bị đọc.
  Command: grep -rn "register(\|TOOLS\b\|from tools.registry import" --include='*.py' \
           app agent api bridge auth db tools | grep -v "def register" | grep -v "tools/registry.py:"
  Pass: chỉ thấy "from tools.registry import Tool" (dataclass — GIỮ). Thấy ai đọc TOOLS/gọi register
        ⇒ đó là reader thật, giữ lại hoặc migrate reader đó sang DI trước, báo Wyatt.

PRE-1503: LLM client của GD0-CHAT dựng ở đâu — tái dùng đường nào?
  Trạng thái: ⏳ ĐỌC api/chat.py + app/main.py. Xác định factory TogetherClient để LLMDrafter
        dùng LẠI (KHÔNG new provider path). Nếu chat dựng inline khó tái dùng ⇒ extract 1 factory
        thuần trong app/main.py, KHÔNG đổi hành vi chat.

PRE-1504: api/webhook.py build_router chữ ký hiện tại (drafter + gì nữa?)
  Trạng thái: ⏳ ĐỌC §48-70. Biết đủ tham số để ráp trong main.py (sender, session_factory,
        identity resolver…). Xác nhận nó KHÔNG tự verify signature (nếu có, đó là điểm dev-gate Q1).
```

---

## §7 — Execute Steps

> Mỗi phase: RISK **đề xuất**, Wyatt ký. Floor rule: ALLOWED_FILES giao RISK_PATHS
> (`tools/registry.py`, `api/webhook.py`, `bridge/`) ⇒ tối thiểu `medium`.
> KHÔNG migration nào ở spec này (wiring, không schema).

### Phase P1 — Dọn dead code loại-2 + sửa comment nói dối

<!-- ADP:PHASE P1 -->
STATUS: IN_PROGRESS
ROADMAP: GD0-DRAFTER
GOAL: `storage/base.py`+`storage/local.py`+`storage/__init__.py` bị xoá; `tools/registry.py::register()` + `TOOLS` global bị xoá (GIỮ `Tool` dataclass); comment "no Drafter yet" ở `app/main.py:16-19` + `api/webhook.py:8` sửa thành sự thật (LLMDrafter tồn tại từ spec 13, chưa mount vì PRE-004+PDPL). GATE_FULL xanh sau khi xoá = chứng minh code đã chết.
APPROACH: Xoá thuần sau PRE-1501/1502 xác nhận 0 reader — nếu PRE thấy reader, DỪNG báo Wyatt (không tự migrate trong phase dọn). `Tool` dataclass GIỮ nguyên (đó là shape sống DI dùng). Comment sửa: nêu đúng trạng thái "impl có (spec 13), chưa mount — chờ GD0-ZALO/PRE-004 + chủ PDPL", không hứa hẹn thời điểm.
ALLOWED_FILES: storage/, tools/registry.py, app/main.py, api/webhook.py, tests/test_runtime_wiring.py, docs/tasks/15-Task-OhanaAISeller-RuntimeWiring.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/ -q -m 'not live' -x
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (ĐỀ XUẤT — floor: `tools/registry.py` + `api/webhook.py` ∈ RISK_PATHS. Không high: chỉ xoá dead + sửa comment, KHÔNG đổi logic đang chạy. ⚠️ mypy scope có `storage` — xoá xong phải gỡ `storage` khỏi lệnh mypy trong GATE_FULL + CLAUDE.md §1, nếu không mypy fail "no such module". Đã áp dụng: `storage` gỡ khỏi `.ai-coder.conf` + CLAUDE.md + GATE_FULL trên đây.)
BLOCKED_BY: PRE-1501 · PRE-1502
SMOKE: N/A code-removal + comment — không service runtime người dùng quan sát; đúng-sai verify bằng GATE_FULL xanh sau khi xoá (suite + mypy + ruff chứng minh 0 reader) + CI.
REVIEW: PASS ref=docs/reviews/15-P1-auto-verdict.json
<!-- /ADP -->

1. PRE-1501/1502 (grep chính xác). Reader ≠ 0 ⇒ STOP báo Wyatt.
2. Test (**RED trước**): assert `import storage` FAIL (ModuleNotFoundError) + `tools.registry` không còn `register`/`TOOLS` (hasattr False), `Tool` còn.
3. Xoá `storage/`; xoá `register()`+`TOOLS`; gỡ `storage` khỏi mypy scope (GATE_FULL + §10 + CLAUDE.md §1).
4. Sửa 2 comment.
5. **STOP+WAIT**.

### Phase P2 — Verify Tool-shape + factory ráp tool set

<!-- ADP:PHASE P2 -->
STATUS: TODO
ROADMAP: GD0-DRAFTER
GOAL: Test chứng minh `build_size_tool`/`build_shipping_tool`/`build_order_status_tool` trả `Tool` hợp lệ: `name` non-empty, `parameters` là JSON-schema dict, **`parameters` KHÔNG chứa key `user_id`/`shop_id`** (bất biến R1.1), `handler` async 3-tham-số, `kind=="read"`. `build_grounding_tools(session_factory, ohana_client) -> list[Tool]` ráp đúng 3 tool, tên duy nhất, tất định.
APPROACH: Tool-shape ĐÃ khớp (viết cùng `Tool` dataclass) — verify là chốt hiện trạng + chặn phân kỳ tương lai, KHÔNG sửa tool. `build_grounding_tools` là hàm THUẦN (nhận dep, trả list) — de-orphan tools bằng một điểm ráp có test, chưa cần main.py. Assert R1.1 cơ học: duyệt `t.parameters` (đệ quy `properties`) không có `user_id`/`shop_id`.
ALLOWED_FILES: tools/registry.py, tools/wiring.py, tests/test_runtime_wiring.py, docs/tasks/15-Task-OhanaAISeller-RuntimeWiring.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_runtime_wiring.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: medium (ĐỀ XUẤT — floor: `tools/registry.py` ∈ RISK_PATHS. Không high: hàm thuần + test, không đường gửi. Q3 quyết `build_grounding_tools` đặt `registry.py` hay `wiring.py` mới.)
BLOCKED_BY: P1 DONE
SMOKE: N/A hàm thuần assert bằng test tất định (đưa dep → 3 Tool đúng); không service runtime quan sát.
REVIEW: (chờ execute)
<!-- /ADP -->

1. Test (**RED trước**): (a) mỗi `build_*_tool` trả `Tool` đủ field; (b) `parameters` không rò `user_id`/`shop_id`; (c) `build_grounding_tools` trả 3 tool tên duy nhất.
2. Viết `build_grounding_tools` (vị trí theo Q3).
3. **STOP+WAIT**.

### Phase P3 — Dựng LLMDrafter trong main.py + integration test chuỗi (UNMOUNTED)

<!-- ADP:PHASE P3 -->
STATUS: TODO
ROADMAP: GD0-DRAFTER
GOAL: `app/main.py` dựng `LLMDrafter(<together_client tái dùng GD0-CHAT>, session_factory, tools=build_grounding_tools(...))` + ráp `webhook.build_router(drafter, …)` NHƯNG **KHÔNG `include_router`** (hoặc dev-gate theo Q1). Integration test: fake `InboundMessage` → `receive_and_draft(drafter, …)` → `policy_gate` park → **1 `PendingReply` row** với `intent`/`confidence` từ LLM (fake client tất định), `MockZaloSender.send` **KHÔNG được gọi**; draft KHÔNG chứa "Ohana"/"trợ lý ảo"/"AI" (regex trên output). Router `chat`/`inbox`/`admin` đang mount KHÔNG đổi hành vi.
APPROACH: Tái dùng `TogetherClient` của `GD0-CHAT` (PRE-1503) — KHÔNG provider path thứ hai. Webhook giữ UNMOUNTED (§1.3): drafter được dựng + truyền vào `build_router`, router có thể để biến local hoặc dev-gate — quyết ở Q1. Integration test gọi `receive_and_draft` trực tiếp (không qua HTTP mount) với fake LLM tất định ⇒ chứng minh chuỗi nội bộ đúng mà không mở cửa khách. Đây là de-orphan bằng dựng+test, không bằng mount.
ALLOWED_FILES: app/main.py, api/webhook.py, tests/test_runtime_wiring.py, docs/tasks/15-Task-OhanaAISeller-RuntimeWiring.md, docs/reviews/, docs/smokes/
GATE: .venv/bin/python -m pytest tests/test_runtime_wiring.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing db bridge tools api auth && .venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
RETRY: 0/3
RISK: high (ĐỀ XUẤT — chạm đường customer-draft (orchestrator chain + `api/webhook.py`) dù chưa mount; PDPL-adjacent. Wyatt sync diff review trước checkpoint. Hạ medium nếu Wyatt xác nhận unmounted + fake-LLM test đủ tách khỏi money/khách.)
BLOCKED_BY: P2 DONE · PRE-1503 · PRE-1504 · Q1 (mount mode)
SMOKE: PASS ref=docs/smokes/15-P3.md — có service runtime (app khởi động với drafter dựng). Điền OBSERVED bằng `uvicorn app.main:app` boot log THẬT + assert `/api/chat` vẫn 200 + webhook route vắng mặt (hoặc 404 nếu unmounted). KHÔNG viết "OK".
REVIEW: (chờ execute — RISK:high cần human= ký REVIEWED_BY bound cùng diff)
<!-- /ADP -->

1. Test (**RED trước**): integration chuỗi park + regex no-"Ohana" + `MockZaloSender` không gọi + chat/inbox smoke không đổi.
2. PRE-1503/1504. Dựng LLMDrafter + ráp router (unmounted/dev-gate theo Q1).
3. Smoke: boot uvicorn thật, ghi `docs/smokes/15-P3.md`.
4. **STOP+WAIT**.

### Phase P4 — Đóng vòng: ISSUE-026 + L3

<!-- ADP:PHASE P4 -->
STATUS: TODO
ROADMAP: GD0-DRAFTER
GOAL: `KNOWN_ISSUES.md` ISSUE-026 cập nhật: phần đã nối (drafter dựng, tool set ráp) → đóng; phần CÒN hoãn (live mount, snapshot capture, TTL, worker drain → real sender) ghi rõ thuộc `GD0-ZALO`/PRE-004. L3 sinh lại phản ánh coverage. `docs/ROADMAP.md` không sửa tay ngoài note nếu cần.
APPROACH: Đóng đúng phần đã làm, KHÔNG khai đóng phần còn hoãn (silent-wrong). ISSUE mới nếu cần cho "webhook chưa mount = đường khách chưa mở" để không ai tưởng đã xong.
ALLOWED_FILES: docs/memory/KNOWN_ISSUES.md, docs/ROADMAP.md, docs/tasks/15-Task-OhanaAISeller-RuntimeWiring.md, docs/reviews/, docs/smokes/
GATE: bash .claude/tools/adp-roadmap.sh "$PWD"
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && bash .claude/tools/adp-roadmap.sh "$PWD"
RETRY: 0/3
RISK: low (ĐỀ XUẤT — ALLOWED_FILES toàn docs, KHÔNG giao RISK_PATHS. Diff docs-only máy verify.)
BLOCKED_BY: P3 DONE
SMOKE: N/A diff docs-only — bằng chứng là L3 sinh lại (coverage GD0-DRAFTER), chính là GATE máy verify.
REVIEW: (chờ execute)
<!-- /ADP -->

1. ISSUE-026 cập nhật (đóng phần nối, ghi phần hoãn).
2. Sinh lại L3.
3. **STOP+WAIT**.

---

## §8 — DB Changes

**KHÔNG có.** Spec này thuần wiring — không migration, không cột, không bảng. (Cột `snapshot`/`expires_at`/`label` + `webhook_event_log` đã có từ spec 14; đường GHI vào chúng là runtime hoãn, ngoài scope §3.)

---

## §10 — Post-checks

```bash
.venv/bin/python -m pytest tests/ -q -m 'not live'
.venv/bin/mypy app agent retrieval parsing db bridge tools api auth   # ⚠️ 'storage' GỠ sau P1
.venv/bin/ruff check . --no-cache && .venv/bin/ruff format --check . --no-cache
.venv/bin/uvicorn app.main:app --port 8099 &   # boot thật cho smoke P3; Ctrl-C sau khi assert
```

⚠️ **Sau P1, `storage` biến mất** ⇒ lệnh mypy trong GATE_FULL, §10 này, và CLAUDE.md §1 phải GỠ `storage` khỏi danh sách, nếu không mypy fail "no such module". Đây là hệ quả cơ học của việc xoá — đừng để sót.

---

## §11 — Deliverables

`storage/` (xoá) · `tools/registry.py` (−`register`/`TOOLS`, +có thể `build_grounding_tools`) · `tools/wiring.py` (mới nếu Q3) · `app/main.py` (+dựng LLMDrafter, sửa comment) · `api/webhook.py` (sửa comment) · `tests/test_runtime_wiring.py` · `docs/smokes/15-P3.md` · `docs/memory/KNOWN_ISSUES.md` · `docs/ROADMAP-STATUS.md` (máy sinh).

Commit: `adp/15-Task-OhanaAISeller-RuntimeWiring phase-<id>: checkpoint` (do `adp-checkpoint.sh` viết).

---

## §12 — Constraints

🚫 **KHÔNG `include_router(webhook)` live** — `GD0-ZALO`, cần signature-verify (PRE-004) + chủ PDPL. Ranh giới §1.3.
🚫 **KHÔNG tạo LLM provider path thứ hai** — tái dùng `TogetherClient` của `GD0-CHAT`. Client mới = luồng song song mới.
🚫 **KHÔNG để `user_id`/`shop_id` vào `Tool.parameters`** — bất biến R1.1; P2 assert.
🚫 **KHÔNG capture snapshot / tính TTL / drain worker ở spec này** — runtime hoãn, chạm orchestrator draft behavior.
🚫 **KHÔNG xoá `storage`/`register()` trước khi PRE-1501/1502 xác nhận 0 reader** — grep chính xác, không tin số audit.
🚫 **KHÔNG quên gỡ `storage` khỏi mypy scope** sau P1 (GATE_FULL + §10 + CLAUDE.md §1).
🚫 **KHÔNG để integration test gọi `sender.send()`** — nhánh park, không auto-send.
🚫 **KHÔNG đổi hành vi `chat`/`inbox`/`admin`** đang mount — smoke P3 chứng minh.
🚫 Self-certify DONE ngoài `adp-checkpoint.sh`.

---

## §13 — Tracking

| Phase | Nội dung | STATUS | RISK (đề xuất) |
|---|---|---|---|
| P1 | Dọn `storage/*` + `register()`/`TOOLS` + sửa 2 comment cũ | TODO | medium |
| P2 | Verify Tool-shape + `build_grounding_tools` factory | TODO | medium |
| P3 | Dựng LLMDrafter trong main.py + integration test (UNMOUNTED) | TODO | high |
| P4 | Đóng ISSUE-026 phần đã nối + L3 | TODO | low |

---

## §14 — Open questions (Wyatt quyết — spec KHÔNG tự chốt)

**Q1 · Webhook: unmounted hay dev-gate mount?** Đề xuất **unmounted** (an toàn nhất, PDPL không chạy kể cả dev). Dev-gate mount (`OHANA_ENV=="dev"`, signature fail-closed, `MockZaloSender`) cho phép test qua HTTP thật nhưng mở đường khách-vào ở dev. Chọn unmounted trừ khi cần HTTP e2e ngay.

**Q2 · RISK tiers.** Đề xuất P1=medium, P2=medium, P3=**high** (customer-draft path dù unmounted, PDPL-adjacent), P4=low. Hạ P3→medium nếu Wyatt thấy unmounted + fake-LLM đủ tách. Wyatt ký.

**Q3 · `build_grounding_tools` đặt đâu?** `tools/registry.py` (cùng `Tool`, ít file) hay `tools/wiring.py` mới (tách "định nghĩa shape" khỏi "ráp instance")? Đề xuất `wiring.py` — registry.py vừa xoá `register()`, giữ nó thuần dataclass.

**Q4 · `storage/*`: xoá hẳn hay giữ với điều kiện gỡ?** Đề xuất **xoá** (fork residue, 0 reader, chưa spec nào cần S3). Nếu giữ cho GĐ tương lai, CLAUDE.md §4 buộc "exclusion phải chết cùng lý do" ⇒ phải viết điều kiện gỡ đo được. Xoá đơn giản hơn — port lại khi thật cần.

**Q5 · Snapshot capture — spec kế tiếp hay gộp?** Spec này KHÔNG capture (đổi orchestrator draft). Xác nhận để một spec runtime sau (`GD0-ZALO`-cùng-cụm hoặc riêng) nhận: capture tier-1 tại T0 vào cột `snapshot`, TTL, worker drain. Ghi để không trôi.
