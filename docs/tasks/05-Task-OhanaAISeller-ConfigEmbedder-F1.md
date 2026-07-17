# 05-Task-OhanaAISeller-ConfigEmbedder-F1

<!-- spec-generator v2.3 · Branch B (raw brief từ Wyatt, no v3 marker) -->
<!-- PROJECT: Ohana AI Seller. Fix ISSUE-016 (high) — build app/config.py + wire embedder THẬT cho F1. -->
<!-- ADP:MANIFEST inherit từ ohana-ai/CLAUDE.md §5. KHÔNG override. -->
<!-- Renumber note: DEC-OHANA-01 từng nhãn "spec 05 = real login" / "spec 06 = staging" — nhãn đó nay lùi thành 06/07. Spec 05 (file này) = config+embedder, foundational hơn login. -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ohana AI Seller — `app/config.py` + wire OpenAIEmbedder thật cho F1 |
| Parent | ISSUE-016 (KNOWN_ISSUES.md, high) · giải quyết nợ từ spec 01 Phase 3 (F1 tick DONE nhưng FakeEmbedder) + spec 04 P2 (`_DeterministicDevEmbedder` band-aid) |
| Depends-on | Spec 04 = 100% DONE (`api/admin.py default_embedder()` + safety gate đã land). Real OpenAI key cho **live acceptance** (không cho gate). |
| Owner | R: Tân / coder (next session) · A: Wyatt (spec approval + RISK tier finalize) |
| Branch | `feat/config-embedder-f1` (tạo từ `main` @ merge b93b8ed) |
| Duration ước lượng | 1–2 ngày (P0+P1); P2 optional +0.5 ngày |
| Spec type | Full (14-section, Ohana-adapted — §4 priority filter, KHÔNG Survival Framework) |
| Workflow mode | IMPLEMENT |
| inherited_from | — (Branch B, audit-grounded 2026-07-17) |
| RISK finalized | P0=medium · P1=medium · P2=medium (Wyatt lock 2026-07-17, §14 Q3). No RISK_WAIVER. |

> **Priority order (Ohana):** safety → user trust → stability → growth. §4 dùng bộ này.

---

## §1 — Problem Statement

F1 wiki-RAG được tick **DONE** ở spec 01 Phase 3 — nhưng **chưa từng chạy với embedder thật một lần nào**. Gate `tests/test_wiki_rag.py` dùng `FakeEmbedder` inline (map text → vector bằng keyword-overlap, không gọi OpenAI). "Xanh" chứng minh pipeline chunk→store→nearest-neighbor đúng, KHÔNG chứng minh embedding thật hoạt động.

**Root cause (đã verify on-disk 2026-07-17):**

| Bằng chứng | Chi tiết |
|---|---|
| `OpenAIEmbedder()` → `ModuleNotFoundError` | `agent/providers/openai_embedder.py:7` `from app.config import get_settings` |
| `app/config.py` chưa bao giờ tồn tại | `ls app/config.py` fail · `git log --all -- app/config.py` rỗng |
| Dead code từ drnickv4 port | `OpenAIEmbedder` + `OpenAIClient` (agent/providers/openai_client.py:13) đều import `app.config`, chưa wire vào live path |
| Band-aid ở spec 04 P2 | `api/admin.py default_embedder()` trả `_DeterministicDevEmbedder()` (hash-based) vô điều kiện; `app/main.py:55` truyền vào admin router |

**Nguy cơ nếu không fix (đã ghi ISSUE-016 high):** Tân land wiki thật (PRE-003) → ingest qua placeholder → `{"success": true, "chunks": N}` với hash vector → `search_wiki` trả chunk gần-ngẫu-nhiên → **AI trả lời khách sai, không stack trace**. Spec 04 P2 đã gate `_DeterministicDevEmbedder.embed()` raise ngoài dev (chặn silent-wrong ở prod) — nhưng đó là chặn đường, KHÔNG mở đường tới embedding thật. Spec này mở đường.

---

## §2 — Goal

**VI:** Build `app/config.py` (Pydantic Settings — foundation dùng chung cho mọi provider), wire `OpenAIEmbedder` thật vào F1 qua factory chọn theo env, và **re-verify F1 end-to-end với embedding thật** (live acceptance, không phải FakeEmbedder). Sau spec này, tuyên bố "F1 dùng được cho khách thật" mới có căn cứ.

**EN:** Build the missing `app/config.py` settings foundation, wire the real `OpenAIEmbedder` into F1's ingest/search path via an env-driven factory, and re-verify F1 end-to-end against real OpenAI embeddings — closing the gap that let F1 be marked DONE while never running with a real embedder.

**DoD (Definition of Done) — đọc kỹ split gate vs acceptance:**
1. `app/config.py` tồn tại: `Settings(BaseSettings)` + `get_settings()` (lru_cache); `openai_api_key`, `openai_embed_model` (default `"text-embedding-3-small"`), `openai_model`, `reasoning_models`.
2. `OpenAIEmbedder()` import + instantiate được (không còn `ModuleNotFoundError`).
3. `default_embedder()` chọn theo env: key có → `OpenAIEmbedder`; không key + dev → `_DeterministicDevEmbedder`; không key + ngoài dev → raise (giữ invariant P2).
4. **Deterministic gate** (`-m 'not live'`, KHÔNG gọi OpenAI): verify config-load + factory-selection-logic + dim-contract (1536) + safety gate P2 còn nguyên. Đây là thứ `adp-checkpoint.sh` chạy.
5. **Live acceptance** (`-m live`, real OPENAI_API_KEY): ingest 1 doc thật qua `OpenAIEmbedder` → `search_wiki` → chunk chứa câu trả lời thắng nearest-neighbor. **Chạy tay 1 lần bởi Wyatt/Tân với real key, log evidence.** ⚠️ Gate tự động KHÔNG tự-certify được cái này — đó chính là cái bẫy đã tạo ra ISSUE-016. DoD #5 chỉ tick khi live run PASS thật.
6. `-m 'not live'` full suite vẫn xanh (46 + test mới), ruff sạch.

---

## §3 — Scope

### Sub-task A (Phase P0) — `app/config.py` Settings foundation

**What:** Tạo module config chung mà `OpenAIEmbedder` + `OpenAIClient` cùng import. Chỉ build + test load; CHƯA wire vào embedder (đó là P1).

**Files:**
- `app/config.py` NEW — `Settings(BaseSettings)` + `get_settings()` lru_cache
- `tests/test_config.py` NEW — gate

**Fields (từ audit — 2 provider tham chiếu):**
- `openai_api_key: str | None` (None cho phép dev không key)
- `openai_embed_model: str = "text-embedding-3-small"` (1536 dims — khớp `Embedding.embedding Vector(1536)`)
- `openai_model: str` (cho OpenAIClient — out scope wiring nhưng field phải có, nếu không import client vẫn vỡ)
- `reasoning_models: frozenset[str] | list[str]` (client dùng — cùng lý do)

**Constraint dim:** `text-embedding-3-small` = 1536 = khớp column hiện tại → **KHÔNG cần Alembic migration**. Đổi sang model khác dim (`text-embedding-3-large` = 3072) SẼ cần migration + reindex — nếu Wyatt muốn model khác, đó là scope riêng, flag STOP.

### Sub-task B (Phase P1) — Wire OpenAIEmbedder + re-verify F1

**What:** Refactor `default_embedder()` thành factory chọn theo env. Thêm deterministic gate cho selection logic + live acceptance test cho embedding thật.

**Files:**
- `api/admin.py` EDIT — `default_embedder()` env-selecting (đọc `get_settings().openai_api_key` + `OHANA_ENV`)
- `tests/test_embedder_wiring.py` NEW — deterministic gate (monkeypatch env, mock `AsyncOpenAI` — verify factory CHỌN đúng class + gọi đúng shape, KHÔNG network)
- `tests/test_wiki_rag_live.py` NEW — `@pytest.mark.live` — ingest→search với real `OpenAIEmbedder` (real key, real network)
- `agent/providers/openai_embedder.py` — chỉ EDIT nếu `get_settings()` shape lệch (kỳ vọng KHÔNG cần — field đã khớp tham chiếu)

**Factory logic (đề xuất — Wyatt xem):**
```
def default_embedder():
    s = get_settings()
    if s.openai_api_key:
        return OpenAIEmbedder()          # real path
    if os.environ.get("OHANA_ENV") == "dev":
        return _DeterministicDevEmbedder()  # dev convenience, hash vectors
    raise RuntimeError("no OPENAI_API_KEY outside dev — refusing placeholder embedder")
```
Giữ nguyên `_DeterministicDevEmbedder.embed()` raise-outside-dev (P2 invariant — defense in depth).

### Sub-task C (Phase P2 — OPTIONAL, Wyatt quyết cắt/giữ) — Consolidate env-reading

**What:** Migrate `get_jwt_secret()` + `db/session.py get_database_url()` sang đọc qua `Settings` để hết "3 chỗ đọc `os.environ` riêng lẻ". Thuần refactor, không đổi behavior.

**Files:** `auth/identity.py` EDIT, `db/session.py` EDIT, `app/config.py` EDIT (thêm `ohana_jwt_secret`, `ohana_env`, `database_url` fields)

**Rủi ro:** `get_jwt_secret()` là RISK path (auth/) — refactor phải giữ NGUYÊN fail-closed-outside-dev logic (test `test_jwt_secret_refuses_public_fallback` phải còn xanh). Nếu Wyatt thấy rủi ro > lợi ích → cắt P2, để 3 chỗ đọc env như cũ (chúng hoạt động đúng).

### Out of scope (defer)

- **LLM client (`OpenAIClient`) wiring cho F2/F3 drafting** — cùng root cause, `app/config.py` ở đây SẼ unblock, nhưng orchestrator chưa có concrete `Drafter` + F3 auto-send gated PRE-004 → spec riêng.
- **Real wiki corpus (PRE-003)** — KHÔNG block: embedder verify được với sample doc. Corpus = content follow-up.
- **Alembic migration cho dim khác** — chỉ khi Wyatt đổi khỏi `text-embedding-3-small`.
- **RS256 upgrade, staging deploy** — spec 06/07.

---

## §4 — Priority Filter (Ohana)

| Priority | Câu hỏi | Đánh giá |
|---|---|---|
| 1. Safety | Wire embedder thật có tạo đường silent-wrong không? | **PASS** — factory raise ngoài dev khi thiếu key; `_DeterministicDevEmbedder` giữ raise-outside-dev. Cả 2 lớp chặn hash-vector chạm prod RAG. |
| 1. Safety | Real OPENAI_API_KEY có leak vào client/git không? | **MUST-PASS** — key CHỈ server-side qua Settings (env). Post-check grep. `app/config.py` KHÔNG hardcode key. |
| 2. User trust | F1 sau spec này có đáng tin cho khách không? | **Điều kiện** — CHỈ khi DoD #5 (live acceptance) PASS thật. Gate tự động không đủ. Đó là điểm mấu chốt của spec này. |
| 3. Stability | Đổi embedder có phá gate 46 test hiện tại không? | **PASS** — DI sạch (`ingest_wiki`/`search_wiki` nhận embedder param). `test_wiki_rag.py` giữ FakeEmbedder (không đổi). Test mới thêm, không sửa cũ. |
| 4. Growth | Unblock gì? | `app/config.py` unblock cả LLM client (F2/F3 spec sau). Foundation. |

### RED FLAG scan (Ohana-adapted)

- [ ] Real API key trong client bundle / git / hardcode? → **NO** (post-check §10)
- [ ] Gate tự-certify "F1 works with real embeddings" mà không chạy real embed? → **NO** — deterministic gate CHỈ verify wiring; semantic = live acceptance tách riêng, DoD #5 ghi rõ đây là bẫy ISSUE-016
- [ ] Đổi dim mà quên migration → vector column mismatch? → **NO** — pin `text-embedding-3-small` (1536), khớp column; đổi model = STOP + spec riêng
- [ ] Refactor auth (P2) làm mất fail-closed-outside-dev của `get_jwt_secret`? → **MUST-VERIFY** — `test_jwt_secret_refuses_public_fallback` phải còn xanh; nếu P2 cắt thì N/A

**Verdict:** PASS với 2 must-pass (không leak key · DoD #5 live acceptance thật) + 1 must-verify (P2 giữ auth invariant nếu làm).

---

## §5 — Source Files & Context

Đọc trước khi run:

1. [ohana-ai/CLAUDE.md](../../CLAUDE.md) — §5 ADP:MANIFEST (RISK_PATHS vừa thêm `api/admin.py`), §7 anti-patterns (đặc biệt mục dev-fallback-phải-gate-env)
2. `docs/memory/KNOWN_ISSUES.md` — **ISSUE-016** (full context) + ISSUE-010 (runtime-import blocked, liên quan)
3. [agent/embedder.py](../../agent/embedder.py) — `Embedder` ABC (interface phải khớp)
4. [agent/providers/openai_embedder.py](../../agent/providers/openai_embedder.py) — adapter dead code (đọc `__init__` để biết `get_settings()` shape cần gì)
5. [agent/providers/openai_client.py](../../agent/providers/openai_client.py) — cũng import `app.config` (biết field `openai_model`/`reasoning_models` để Settings đủ, dù không wire client)
6. [api/admin.py](../../api/admin.py) — `default_embedder()` + `_DeterministicDevEmbedder` (điểm swap + safety gate phải giữ)
7. [parsing/ingest.py](../../parsing/ingest.py) + [tools/wiki.py](../../tools/wiki.py) — injection points (`embedder` param)
8. [tests/test_wiki_rag.py](../../tests/test_wiki_rag.py) — FakeEmbedder gate hiện tại (mẫu cho live test; KHÔNG sửa file này)
9. [db/models.py](../../db/models.py) — `_EMBED_DIM = 1536` (dim contract)
10. `pyproject.toml` — `pydantic-settings` + `openai` đã có; `live` marker

**Recent context:** Spec 04 GĐ0.5 UI đóng 2026-07-17 (merge b93b8ed). ISSUE-016 phát hiện lúc P2 wire admin ingest. RISK_PATHS đã thêm `api/inbox.py` + `api/admin.py` (meta-sync 7dfae1d).

---

## §6 — Pre-flight Checks

```bash
cd /Users/wyattngo/Sites/localhost/ohana-ai

# PF1. Working tree clean, branch mới
git status                                   # Expected: clean (main @ b93b8ed sau merge)
git checkout -b feat/config-embedder-f1
git branch --show-current                    # Expected: feat/config-embedder-f1

# PF2. app/config.py THẬT chưa tồn tại (xác nhận vấn đề)
ls app/config.py 2>&1                         # Expected: No such file
git log --all --oneline -- app/config.py      # Expected: rỗng
.venv/bin/python -c "from agent.providers.openai_embedder import OpenAIEmbedder; OpenAIEmbedder()" 2>&1 | tail -1
# Expected: ModuleNotFoundError: No module named 'app.config'
# → đây là RED baseline; P0 làm nó biến mất

# PF3. Field 2 provider cần (Settings phải phủ hết)
grep -rhoE "settings\.[a-z_]+" agent/providers/openai_embedder.py agent/providers/openai_client.py | sort -u
# Expected: settings.openai_api_key, settings.openai_embed_model, settings.openai_model, settings.reasoning_models
# Red flag: field lạ ngoài 4 cái này → Settings thiếu → import vẫn vỡ

# PF4. Dim contract
grep -rn "_EMBED_DIM\|Vector(1536)\|VECTOR_DIM" db/models.py db/migrations/versions/0001_initial_tenant_first.py
# Expected: 1536 ở cả 3. text-embedding-3-small = 1536 → no migration.

# PF5. Baseline gate xanh (46) + ruff sạch trước khi động
.venv/bin/python -m pytest tests/ -q -m 'not live'   # Expected: 46 passed
.venv/bin/python -m ruff check api/ tests/ auth/ app/ agent/  # Expected: All checks passed

# PF6. deps có sẵn
grep -nE "pydantic-settings|openai>" pyproject.toml   # Expected: cả 2 present
```

**STOP nếu PF trả red flag ngoài dự kiến → paste output, hỏi Wyatt.**

---

## §7 — Execute Steps

> TDD ordering: gate test RED trước impl. STOP+WAIT giữa phase (RISK:medium = 1 confirm ANCHOR).

### Phase P0 — `app/config.py` Settings foundation

<!-- ADP:PHASE P0 -->
STATUS: DONE
EVIDENCE: commit=897ba1f, gate_exit=0, duration=11s, review=PASS(judge=APPROVE,model=haiku,bound=5165de25e1ed,tier=medium), ran=2026-07-17T23:40
GOAL: `app/config.py` với `Settings(BaseSettings)` + `get_settings()` lru_cache phủ 4 field 2 provider cần; **`OpenAIEmbedder()` import được (hết ModuleNotFoundError — F1 path unblocked)**; gate `test_config.py` PASS.
AMENDED 2026-07-17 (tại ANCHOR P0): GOAL gốc còn đòi "`OpenAIClient()` import được" — SAI. Executor tìm ra `openai_client.py:28` còn import `from app import alert_service` (module `app/alert_service.py` cũng chưa bao giờ tồn tại — ISSUE-010 đã ghi CẢ 2, audit spec 05 của tôi rớt nửa alert_service). `OpenAIClient` là LLM client (F2/F3) — **out scope spec 05** (§3 Out of scope), F1 KHÔNG cần nó. `app/config.py` unblock nửa config; alert_service là blocker riêng cho LLM-client spec sau. Executor encode đúng: `test_openai_client_import_blocked_by_unported_alert_service` là `xfail(strict=True)` — flip thành hard-fail khi ai đó port alert_service, không rot. F1 deliverable (OpenAIEmbedder import) đạt thật.
APPROACH:
  1. TDD gate: viết `tests/test_config.py`: (a) `get_settings()` trả Settings với `openai_embed_model == "text-embedding-3-small"` default, (b) `openai_api_key` None khi env unset (không raise), (c) đọc `OPENAI_API_KEY` từ env khi set, (d) `from agent.providers.openai_embedder import OpenAIEmbedder` không raise ImportError. Confirm RED (app/config.py chưa có → import fail).
  2. Tạo `app/config.py`: `Settings(BaseSettings)` (pydantic-settings), 4 field + default `text-embedding-3-small`, `get_settings()` `@lru_cache`. `model_config = SettingsConfigDict(env_prefix="", ...)` map `OPENAI_API_KEY` → `openai_api_key`.
  3. Verify `OpenAIEmbedder()` instantiate được với key giả (không network — chỉ __init__). `OpenAIClient` import được.
  4. Confirm gate GREEN.
  5. Checkpoint qua adp-checkpoint.sh.
ALLOWED_FILES: app/config.py, tests/test_config.py
GATE: .venv/bin/python -m pytest tests/test_config.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/test_config.py tests/test_wiki_rag.py tests/test_tenant_isolation.py -x -q
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/05-Task-OhanaAISeller-ConfigEmbedder-F1-phase-P0.json
<!-- /ADP -->

### Phase P1 — Wire OpenAIEmbedder + re-verify F1

<!-- ADP:PHASE P1 -->
STATUS: DONE
EVIDENCE: commit=b4a7119, gate_exit=0, duration=3s, review=PASS(judge=APPROVE,model=haiku,bound=7cfe51e5521f,tier=medium), ran=2026-07-18T00:31
GOAL: `default_embedder()` chọn embedder theo env (key→real, no-key+dev→fake, no-key+prod→raise); deterministic gate verify selection-logic + dim-contract; live acceptance test (`-m live`) ingest→search với real OpenAIEmbedder soạn sẵn để Wyatt/Tân chạy.
APPROACH:
  1. TDD gate: `tests/test_embedder_wiring.py` (deterministic, KHÔNG network): (a) monkeypatch `openai_api_key` set → `default_embedder()` trả instance `OpenAIEmbedder` (mock `AsyncOpenAI` để __init__ không cần key thật), (b) no key + `OHANA_ENV=dev` → `_DeterministicDevEmbedder`, (c) no key + `OHANA_ENV` unset → raise RuntimeError, (d) `OpenAIEmbedder.embed()` với mock client trả đúng shape `list[list[float]]` dim 1536. Confirm RED (factory hiện trả fake vô điều kiện).
  2. Refactor `api/admin.py default_embedder()` theo factory logic §3 B. Giữ `_DeterministicDevEmbedder.embed()` raise-outside-dev (defense in depth).
  3. Viết `tests/test_wiki_rag_live.py` `@pytest.mark.live`: real `OpenAIEmbedder`, ingest 1 doc mẫu (return-policy text như test_wiki_rag) → `search_wiki` → assert chunk đúng thắng. **Đây KHÔNG chạy trong GATE** (`-m 'not live'` loại nó). Nó là acceptance Wyatt/Tân chạy tay.
  4. Confirm deterministic gate GREEN + full `-m 'not live'` xanh (không regress).
  5. Checkpoint qua adp-checkpoint.sh.
  6. **ANCHOR — báo Wyatt:** deterministic gate xanh KHÔNG = F1 verified. DoD #5 chờ live run. Cung cấp lệnh: `OPENAI_API_KEY=... .venv/bin/python -m pytest tests/test_wiki_rag_live.py -m live -x -q`.
ALLOWED_FILES: api/admin.py, tests/test_embedder_wiring.py, tests/test_wiki_rag_live.py, agent/providers/openai_embedder.py
GATE: .venv/bin/python -m pytest tests/test_embedder_wiring.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -x -q -m 'not live'
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/05-Task-OhanaAISeller-ConfigEmbedder-F1-phase-P1.json
AMENDED 2026-07-18 (tại ANCHOR P1, Wyatt chọn "chấp nhận deviation"): §3 B pseudocode đề xuất `default_embedder()` RAISE khi no-key+non-dev. Executor phát hiện `app/main.py:55` gọi `default_embedder()` lúc IMPORT (không per-request) → raise ở factory crash CẢ app (mọi route, không chỉ wiki-ingest). Thay bằng: factory KHÔNG raise, no-key→`_DeterministicDevEmbedder`, dựa vào `embed()` raise-outside-dev. Safety property GIỮ NGUYÊN — verify độc lập: `parsing/ingest.py` gọi `embed()` (line 19) TRƯỚC mọi `s.add`/`commit` (line 25-34) → raise short-circuit trước DB write, không partial-state. Khớp convention per-request của codebase (`api/mock_auth.py::_is_dev_env`). Reviewer + Wyatt + main-session verify đồng thuận deviation TỐT HƠN spec (crash-1-route vs crash-cả-app, seller UI vẫn sống khi thiếu key). Pseudocode §3 B vốn ghi "đề xuất — Wyatt xem", không frozen.
<!-- /ADP -->

### Phase P2 — OPTIONAL: Consolidate env-reading (Wyatt quyết cắt/giữ)

<!-- ADP:PHASE P2 -->
STATUS: IN_PROGRESS
GOAL: `get_jwt_secret()` + `db/session.py get_database_url()` đọc qua `Settings`; ZERO đổi behavior (fail-closed-outside-dev của jwt secret giữ nguyên); mọi test cũ xanh.
APPROACH:
  1. TDD: KHÔNG viết test mới — dùng test hiện có làm regression guard. Confirm `test_jwt_secret_refuses_public_fallback` + `test_web_scaffold` + tenant-isolation xanh TRƯỚC refactor (baseline).
  2. Thêm `ohana_jwt_secret`, `ohana_env`, `database_url` vào Settings.
  3. Refactor `get_jwt_secret()` đọc `get_settings().ohana_jwt_secret` — GIỮ NGUYÊN logic: có → dùng; không + dev → dev fallback literal; không + prod → raise. KHÔNG được đổi ngữ nghĩa.
  4. Refactor `db/session.py get_database_url()` tương tự.
  5. Confirm TẤT CẢ test cũ vẫn xanh (đặc biệt `test_jwt_secret_refuses_public_fallback`, `test_dev_embedder_refuses_to_run_outside_dev`).
  6. Checkpoint.
ALLOWED_FILES: app/config.py, auth/identity.py, db/session.py
GATE: .venv/bin/python -m pytest tests/test_web_scaffold.py tests/test_config.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -x -q -m 'not live'
RETRY: 0/3
RISK: medium
REVIEW: PASS ref=docs/reviews/05-Task-OhanaAISeller-ConfigEmbedder-F1-phase-P2.json
NOTE 2026-07-18: Path 1 (fresh `Settings()` per call, KHÔNG `get_settings()` cached) — né cache-staleness trap trên security path `get_jwt_secret()`. Behavior-preserving: 3 nhánh fail-closed byte-identical, db default khớp `_DEFAULT_URL` cũ. Executor prove test security còn bắt được revert (xóa nhánh raise → test FAILED). Không cần chạm test file / conftest.py (brief lo path 2/3 — path 1 né được).
<!-- /ADP -->

> **P2 là OPTIONAL.** Nếu Wyatt cắt tại spec approval → mark P2 `CANCELLED` + rationale "3 chỗ đọc env hoạt động đúng, refactor rủi ro auth > lợi ích gọn". Spec vẫn DONE với P0+P1.

---

## §8 — DB Changes

**N/A** — `text-embedding-3-small` = 1536 = khớp `Embedding.embedding Vector(1536)` hiện tại. KHÔNG migration.

⚠️ **Nếu Wyatt đổi sang model khác dim** (vd `text-embedding-3-large` = 3072): CẦN Alembic migration đổi `Vector(1536)` → `Vector(3072)` + **reindex mọi embedding cũ** (vector cũ dim 1536 không query được với query vector 3072). Đó là scope RIÊNG, STOP + spec mới — KHÔNG nhét vào spec này.

---

## §9 — i18n

**N/A** — backend-only, không UI string.

---

## §10 — Post-checks

```bash
# PC1. Real API key KHÔNG leak (git/hardcode)
grep -rnE "sk-proj-[A-Za-z0-9]|sk-[A-Za-z0-9]{20}" app/ agent/ api/ tests/ 2>/dev/null
# Expected: zero hits. app/config.py đọc từ env, KHÔNG hardcode.

grep -rn "openai_api_key\s*=\s*['\"]sk" app/ 2>/dev/null   # Expected: zero (không default key literal)

# PC2. ModuleNotFoundError đã hết
.venv/bin/python -c "from agent.providers.openai_embedder import OpenAIEmbedder; OpenAIEmbedder(api_key='test-fake')" && echo "import OK"
# Expected: import OK (instantiate với key giả, không network ở __init__)

# PC3. Deterministic gate + full suite (KHÔNG live)
.venv/bin/python -m pytest tests/ -q -m 'not live'
# Expected: all green (46 + test_config + test_embedder_wiring)

# PC4. dim contract giữ nguyên
grep -rn "1536" db/models.py app/config.py tests/test_embedder_wiring.py
# Expected: embed_model default → 1536 consistent

# PC5. ruff
.venv/bin/python -m ruff check app/ api/ agent/ auth/ db/ tests/
# Expected: All checks passed

# PC6. safety gate P2 còn nguyên (silent-wrong vẫn chặn)
.venv/bin/python -m pytest tests/test_admin_ui.py::test_dev_embedder_refuses_to_run_outside_dev -x -q
.venv/bin/python -m pytest tests/test_web_scaffold.py -x -q  # jwt fail-closed nếu P2 làm
# Expected: xanh

# ===== LIVE ACCEPTANCE (Wyatt/Tân chạy tay — KHÔNG phải gate) =====
# PC7. F1 end-to-end với embedding THẬT — đây là DoD #5, thứ ISSUE-016 thiếu
OPENAI_API_KEY=<real> DATABASE_URL=<pg> .venv/bin/python -m pytest tests/test_wiki_rag_live.py -m live -x -q
# Expected: PASS — ingest doc thật → search → chunk đúng thắng nearest-neighbor với real embeddings
# ⚠️ CHỈ khi cái này PASS mới được tuyên bố "F1 dùng được cho khách". Log kết quả vào SESSION_LOG.
```

---

## §11 — Deliverables

**Files created:**
- `app/config.py`
- `tests/test_config.py`
- `tests/test_embedder_wiring.py`
- `tests/test_wiki_rag_live.py`

**Files modified:**
- `api/admin.py` (`default_embedder()` env-selecting)
- `agent/providers/openai_embedder.py` (chỉ nếu shape lệch — kỳ vọng không)
- (P2 nếu làm) `auth/identity.py`, `db/session.py`

**Commit drafts** (do NOT commit — checkpoint script làm):
```
adp/05 phase-p0: app/config.py Settings foundation
adp/05 phase-p1: wire OpenAIEmbedder + live F1 acceptance test
adp/05 phase-p2: consolidate env-reading qua Settings   (nếu không cắt)
```

**Sau khi merge:** update KNOWN_ISSUES ISSUE-016 → RESOLVED (sha) CHỈ SAU KHI live acceptance PC7 PASS. Update CLAUDE.md §2 F1 line bỏ cảnh báo embedder.

---

## §12 — Constraints

- ONE concern per commit. P0/P1 (+P2) checkpoint riêng.
- STOP+WAIT sau mỗi phase — RISK:medium = 1 confirm ANCHOR.
- **Deterministic gate KHÔNG được gọi OpenAI thật** — giữ `-m 'not live'` deterministic + offline. Live test mang marker `live`, loại khỏi gate. Vi phạm = tái tạo ISSUE-016 (gate xanh giả).
- **KHÔNG tuyên bố F1 DONE/verified chỉ vì deterministic gate xanh** — DoD #5 (live acceptance PC7) là điều kiện thật. adp-checkpoint đóng phase, KHÔNG đóng ISSUE-016.
- KHÔNG hardcode real API key ở đâu — Settings đọc env.
- KHÔNG đổi embedding model khỏi dim 1536 mà không migration (§8).
- KHÔNG sửa `tests/test_wiki_rag.py` (FakeEmbedder gate giữ nguyên — nó test pipeline, không test embedder).
- KHÔNG bỏ safety gate `_DeterministicDevEmbedder.embed()` raise-outside-dev.
- (P2) KHÔNG đổi ngữ nghĩa `get_jwt_secret()` fail-closed — chỉ đổi NGUỒN đọc (env → Settings), giữ hành vi.
- KHÔNG chạm `agent/orchestrator.py`, `agent/policy_gate.py`, `bridge/`, `db/migrations/`, `api/inbox.py`, `api/webhook.py`.
- KHÔNG tick DONE thủ công — adp-checkpoint.sh.

---

## §13 — Tracking

| Phase | Step | Concern | STATUS | Commit | Notes |
|---|---|---|---|---|---|
| P0 | 1 | `test_config.py` RED | [ ] | — | TDD |
| P0 | 2 | `app/config.py` Settings + get_settings | [ ] | — | 4 field |
| P0 | 3 | OpenAIEmbedder/Client import OK | [ ] | — | hết ModuleNotFoundError |
| P0 | 4 | Gate GREEN + checkpoint | [ ] | — | adp-checkpoint |
| P1 | 5 | `test_embedder_wiring.py` RED | [ ] | — | TDD, mock OpenAI |
| P1 | 6 | `default_embedder()` env-selecting | [ ] | — | giữ safety gate |
| P1 | 7 | `test_wiki_rag_live.py` (`-m live`) | [ ] | — | acceptance, không gate |
| P1 | 8 | Gate GREEN + checkpoint + ANCHOR | [ ] | — | báo Wyatt DoD #5 pending |
| P2 | 9 | (optional) migrate jwt/db env → Settings | [ ] | — | giữ auth invariant |
| — | — | **PC7 live acceptance (Wyatt/Tân, real key)** | [ ] | — | **DoD #5 — điều kiện tuyên bố F1** |
| — | — | ISSUE-016 → RESOLVED (chỉ sau PC7) | [ ] | — | update KNOWN_ISSUES + CLAUDE.md |
| — | — | Merge `feat/config-embedder-f1` → main | [ ] | — | sau Wyatt review |

---

## §14 — Open Questions — LOCKED 2026-07-17 (Wyatt directive "lock q1-q4 rồi execute")

- **Q1 — Embedding model → `text-embedding-3-small` (1536).** Khớp `Embedding.embedding Vector(1536)` hiện tại → **KHÔNG Alembic migration**. Đổi model khác dim = scope riêng (§8).
- **Q2 — P2 (consolidate env-reading) → LÀM (giữ).** Migrate `get_jwt_secret`/`db/session` env-reading qua Settings. Ràng buộc: KHÔNG đổi ngữ nghĩa fail-closed của jwt secret (§7 P2 approach).
- **Q3 — RISK tier finalized:** P0 = **medium** (config foundation sẽ giữ secret ở P2 — over-protect dù floor mechanical là low), P1 = **medium**, P2 = **medium**. Không phase nào high: GĐ0.5 chưa có khách thật + 2 lớp safety gate (factory raise + `_DeterministicDevEmbedder` raise-outside-dev) chặn silent-wrong. Không RISK_WAIVER.
- **Q4 — OPENAI_API_KEY cho live acceptance → handoff Wyatt/Tân.** ⚠️ **KHÔNG block code execution:** P0/P1/P2 + deterministic gate chạy không cần key thật (P1 mock `AsyncOpenAI`). CHỈ PC7 (`test_wiki_rag_live.py -m live`, DoD #5) cần real key. **ISSUE-016 giữ OPEN cho tới khi Wyatt/Tân chạy PC7 PASS** — code xong ≠ F1 verified. Executor viết `test_wiki_rag_live.py` sẵn + để lệnh chạy ở ANCHOR P1.

---

*Spec 05. Ohana ADP v2.3. Q1–Q4 LOCKED 2026-07-17. RISK finalized (P0/P1/P2 = medium). Executing.*
