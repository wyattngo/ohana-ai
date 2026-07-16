# PHASE1_DISCOVERY — Ohana AI ↔ drnickv4 port audit

> Sub-phase 1.0 report. Auto-run 2026-07-16 từ Ohana AI session.
> Spec: `docs/tasks/02-Task-Phase1-Bootstrap-Fork-DrNickV4.md` §6.
> Rule: bất kỳ PRE nào unexpected → STOP+WAIT. Không auto-fix.

---

## Summary verdict

**PASS** — mọi PRE (101..108) clear enough để tiến 1.1. **1 spec correction** cần Wyatt xác nhận trước khi tiến (xem §CORRECTIONS bên dưới) + 1 SIGNAL non-blocking cho Phase 2 planning.

---

## PRE-101 — drnickv4 working tree

- `git status --short`: (empty) → clean tree
- Branch: `main`
- HEAD SHA: **`d32b1c19824e49e87a677acfef15ff8115541edb`**

**DRNICKV4_PIN_SHA=d32b1c19824e49e87a677acfef15ff8115541edb** ← pin cho toàn Phase 1 port.

Verdict: PASS.

---

## PRE-102 — db/models.py scope columns

- Tables tồn tại (7): `conversations`, `messages`, `files`, `embeddings`, `financial_audit`, `feedback`, `admin_flags`
- Grep `shop_id|tenant_id`: **0 hit**

**Signal cho Phase 2 (không blocking Phase 1):**
- DrNick single-tenant confirmed. Rewrite `db/models.py` tenant-first ở Phase 2 sẽ phải chạm cả 7 table.
- `financial_audit` — NOT porting (out of scope Ohana).
- `admin_flags` — port shape có thể tái dùng cho feature-flag Ohana (defer decision Phase 2).

Verdict: PASS (signal ghi nhận, không cản Phase 1).

---

## PRE-103 — guardrail.py location

- Path: `/Users/wyattngo/Sites/localhost/drnickv4/.claude/hooks/guardrail.py`
- Đúng directory hooks/ (không phải skills/).
- Additional: `.pyc` cache tồn tại — không port (Python sẽ regenerate).

**R1.13 confirmed:** file có rule `R-NEW-13` money-state (line 109-112) — sẽ adapt thành `intent-safety` placeholder ở Phase 1.3 theo spec §7 Sub-phase 1.3.

Additional DENY rules phát hiện (sẽ evaluate khi port):
- `R3_VERIFY_FALSE` (TLS) — **KEEP as-is**
- `R1_TIER_HINT` / `R1_TIER_FROM_BODY` — **KEEP** (Ohana multi-tenant cần y hệt)
- `R2_SECRET_EQ` — **KEEP**
- `SECRET_LEAK_KNOWN`, `SECRET_LEAK_ASSIGN` — **KEEP**
- `R-NEW-13` money — **REWRITE** thành `intent-safety` placeholder

Verdict: PASS.

---

## PRE-104 — reviewer subagent

- drnickv4 project-level (`drnickv4/.claude/agents/`): `explorer.md`, `reviewer.md`
- User-level (`~/.claude/agents/`): 7 v2.3 agents (bug-fixer, claude-code-guide, coder, output-evaluator, senior-engineer, tech-lead, test-reviewer)
- Ohana project-level: **chưa có** (`ohana-ai/.claude/agents/` không tồn tại)

**Analysis:**
- `reviewer.md` DrNick-specific: reference R1.1..R1.10, S1-S9 checklist, "ONFA PHP behavior via bridge/", milestone doc `drnick-agent-v4-system-design.md`. **KHÔNG port blind** — cần rewrite chunks cho Ohana context ở Phase 5 (khi có policy_gate). Phase 1: skip port, dùng user-level v2.3 agents.
- `explorer.md` generic hơn — có thể port ở Phase 1.3 với changes minimal (đổi "DrNick" → "Ohana", "ONFA PHP" → "Ohana platform REST").

**Decision đề xuất Wyatt:**
- **A**: Phase 1.3 chỉ verify user-level agents đủ, skip port cả 2. (conservative — spec §7 Sub-phase 1.3 step 2 fallback)
- **B**: Port `explorer.md` với rewrite tối thiểu; skip `reviewer.md` tới Phase 5.
- **C**: Port cả 2 với rewrite (blast radius lớn hơn, delay 1.3).

Verdict: PASS — chọn default A theo spec §7 fallback path. Ghi B/C vào KNOWN_ISSUES nếu Wyatt muốn upgrade.

---

## PRE-105 — CI workflow

- File: `.github/workflows/ci.yml` (1 file)
- 2 jobs: `test` (backend) + `frontend` (widget FE — vitest cho web/)

**test job snapshot:**
- Runs on: ubuntu-latest
- Services: postgres (`pgvector/pgvector:pg16`) + redis (`redis:7`)
- Python: 3.11 (pip cache)
- Install: `pip install -e ".[dev]"`
- Steps: guardrail headless → ruff check + format → mypy strict → drift check → alembic upgrade → pytest
- Env: `DATABASE_URL=postgresql+psycopg://drnick:drnick@localhost:5432/drnick`, `REDIS_URL=redis://localhost:6379/0`

**Adaptations needed cho Ohana port ở Phase 1.3:**
- Đổi `drnick:drnick` → `ohana:ohana` (env vars + service creds)
- Rename job/comments "DrNick" → "Ohana"
- Drop `scripts/check_drift.py` step (DrNick-specific, không port ở Phase 1)
- `frontend` job — **skip port** (Ohana chưa có `web/` folder — defer)
- `mypy app db agent tools api auth` — Phase 1 chưa có `tools`, `api`, `auth` folders → adapt scope theo module thực có sau 1.2

Verdict: PASS.

---

## PRE-106 — Alembic skeleton

- `alembic.ini`: OK
- `db/migrations/`: `__pycache__/`, `env.py`, `script.py.mako`, `versions/` — đầy đủ

Verdict: PASS. Port full skeleton ở 1.3 (empty `versions/`, KHÔNG copy migrations DrNick).

---

## PRE-107 — Python + install pattern

- Python: **`>=3.11`** (`pyproject.toml requires-python` + `ruff target-version = "py311"` + `mypy python_version = "3.11"`)
- `.python-version`: **KHÔNG có** — Ohana cần tạo file mới pin `3.11` (hoặc `3.12` nếu Wyatt muốn upgrade — decision required).
- Install pattern: **`pip install -e ".[dev]"`** — pure `[project.optional-dependencies]` extra, KHÔNG dùng uv/poetry/pipenv/PEP-735 dependency-groups.
- `requirements-dev.txt`: KHÔNG có
- `uv.lock` / `poetry.lock` / `Pipfile.lock`: đều KHÔNG có

**DRNICKV4_INSTALL_PATTERN=pip-editable-extra[dev]**

### Runtime deps snapshot (18 packages)
```
fastapi>=0.110         uvicorn[standard]>=0.29    pydantic>=2.6         pydantic-settings>=2.2
sse-starlette>=2.1     python-multipart>=0.0.9    pypdf>=4.0            openpyxl>=3.1
defusedxml>=0.7        openai>=1.30               httpx>=0.27           pyjwt[crypto]>=2.8
sqlalchemy>=2.0        alembic>=1.13              psycopg[binary]>=3.1  pgvector>=0.2.5
redis>=5.0
```

### Dev deps (6 packages)
```
ruff>=0.4    mypy>=1.10    pytest>=8.0    pytest-asyncio>=0.23    pyotp>=2.9    anthropic>=0.40
```

**Ohana Phase 1.1 strip decision (đề xuất — Wyatt confirm khi bootstrap pyproject):**
- **STRIP**: `pyotp` (DrNick 2FA-only, spec 37 P3), `openpyxl` (DrNick xlsx parser — Ohana chưa cần), `anthropic` (DrNick eval-harness spec 43 — Ohana defer tới khi có RAG eval)
- **KEEP tất cả 15 còn lại** — cần cho FastAPI + Pydantic + LLM + Postgres+pgvector + Redis + JWT + Alembic + PDF parsing
- **CONSIDER add**: `zalo-sdk` (Phase 4 wiring — defer), `google-generativeai` hoặc similar nếu Ohana muốn LLM provider khác OpenAI (defer)

### Setuptools packages (drnickv4)
```
app, auth, agent, tools, bridge, db, api, storage, parsing, retrieval
```

Ohana Phase 1.1 skeleton chỉ cần: `app`, `agent`, `retrieval`, `parsing`, `storage` + `agent/providers` sub-package. Còn lại defer.

### Pytest config finding
`[tool.pytest.ini_options]` có `addopts = "-q -m 'not live'"` + custom marker `live`. **Port pattern** — Ohana cũng sẽ có LLM smoke test cần gate.

Verdict: PASS.

---

## PRE-108 — ONFA reference grep

Kết quả grep `onfa|ONFA|wallet|pending_action|ConfirmEvent` trong port targets:

| Target | Result | Action |
|---|---|---|
| `agent/llm_client.py` | 1 hit line 62: comment `# tools — preserving the dispatch path verbatim (R7.4 / ConfirmEvent HALT unchanged).` | **STRIP** comment khi port |
| `agent/embedder.py` | clean | direct copy |
| `providers` **[SPEC ERROR — see CORRECTIONS]** | **path NOT FOUND** — thực tế ở `agent/providers/` (không phải root) | Adjust port command |
| `retrieval` | clean | direct copy |
| `parsing` | clean | direct copy |
| `storage` | clean | direct copy |

Verdict: PASS on grep, **BLOCKING on spec path correction** (xem dưới).

---

## CORRECTIONS — spec 02 §5 path drift

### C-1: `providers/` không ở root drnickv4/ — **APPLIED 2026-07-16**

**Status:** ✅ Wyatt approved. Spec 02 edited: §5 row, §3 scope table, §7 Sub-phase 1.2 ADP block + steps, §11 Deliverables, §13 Tracking table. Verify: `grep -n "agent/providers" docs/tasks/02-*` → 5 hit (all correct).

**Original finding below (for audit trail):**


**Spec §5 nói:**
```
| `providers/` | `providers/` | `test -d drnickv4/providers && ls drnickv4/providers/*.py` | Expected exist |
```

**On-disk reality:**
```
$ find drnickv4 -type d -name "providers" -not -path "*/.*"
/Users/wyattngo/Sites/localhost/drnickv4/agent/providers
```

`providers/` là **sub-package của `agent/`** (imports `from agent.providers import ...`).

**Impact:**
- Spec §7 Sub-phase 1.2 step 2 `cp -R /Users/wyattngo/Sites/localhost/drnickv4/<module> ./` sẽ fail cho `providers` module.
- Port target Ohana cũng phải là `agent/providers/` (không `providers/` ở root — sẽ vỡ import).

**Recommended fix:**
- Update spec §5 row `providers/` → source `agent/providers/`, target `agent/providers/`.
- Update §7 Sub-phase 1.2 module loop list: `agent/llm_client.py`, `agent/embedder.py`, `agent/providers/`, `retrieval/`, `parsing/`, `storage/` (5 module + 1 file, không phải "6 module").
- Update §2 DoD grep exclusions không đổi.

**STOP+WAIT — chờ Wyatt duyệt spec correction trước khi 1.1 bắt đầu.**

### C-2 (non-blocking): §1 stale — repo đã git-init

Spec §1: "`git status` sẽ fail vì chưa `git init`" — thực tế `ohana-ai/` đã là git repo (2 commits, branch `main`, clean tree). Do ADP v2.3 install và session-log commit trước. Không cần fix spec — chỉ ghi nhận.

---

## KNOWN ISSUES ghi nhận (defer)

1. Reviewer subagent port strategy (PRE-104) — pick A/B/C.
2. `.python-version` file — pin `3.11` hay upgrade `3.12`?
3. `openai + anthropic` provider list Ohana — có port full hay strip anthropic tới eval phase?
4. CI `frontend` job — Ohana seller inbox UI framework chưa decide (spec 01 open) → defer port CI FE lane tới sau Phase 3.

---

## Decisions locked (Wyatt approved 2026-07-16)

| ID | Decision | Impact |
|---|---|---|
| **C-1** | ✅ APPLIED — spec 02 edited: `providers/` → `agent/providers/` across §5/§3/§7/§11/§13 | Phase 1.2 loop = 2 files + 4 packages |
| **PRE-104** | ✅ **A** — skip port cả `explorer.md` + `reviewer.md`. Dùng user-level v2.3 agents (7 agents đã có). | Phase 1.3 step 2 = verify only, không port file agent. Reviewer.md port defer tới khi có policy_gate (Phase 5) nếu cần custom. |
| **PRE-107 python** | ✅ **Pin 3.11** (khớp drnickv4) | Phase 1.1: tạo `.python-version` = `3.11`. `pyproject.toml requires-python = ">=3.11"`. Ruff/mypy target py311. |
| **PRE-107 dev-strip** | ✅ **Strip 3**: `pyotp`, `openpyxl`, `anthropic` | Phase 1.1: `pyproject.toml [project.optional-dependencies].dev` = 3 packages (`ruff`, `mypy`, `pytest`, `pytest-asyncio`) instead of 6. Re-add later khi Ohana có 2FA / xlsx / eval-harness use case. |

## Next step

Phase 1.0 GATE PASS → checkpoint đóng phase → phase 1.1 IN_PROGRESS (nếu low→low auto-advance).
