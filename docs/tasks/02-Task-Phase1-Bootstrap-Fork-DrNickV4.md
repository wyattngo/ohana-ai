# 02-Task-Phase1-Bootstrap-Fork-DrNickV4

<!-- spec-generator v2.3 · Child spec của 01-Task-OhanaAISeller-GD0.md Phase 1 -->
<!-- PROJECT: Ohana AI Seller. Fork chọn lọc từ drnickv4/. NOT a full clone. -->
<!-- ADP:PARENT_MANIFEST at ohana-ai/CLAUDE.md §5. This spec extends Phase 1 (1.0..1.3 sub-phases). -->

## §0 — Header

| Field | Value |
|---|---|
| Title | Ohana AI — Phase 1 Bootstrap (Fork DrNickV4 chọn lọc) |
| Parent | [01-Task-OhanaAISeller-GD0.md](01-Task-OhanaAISeller-GD0.md) Phase 1 |
| Depends-on | drnickv4/ @ `main` (SHA phải capture ở PRE-101 và pin vào PHASE1_DISCOVERY.md) |
| Owner | R: Coder (next session) · A: Wyatt (spec approval + tier RISK) |
| Duration ước lượng | 1-2 ngày (nếu PRE-101..108 clear) |
| Spec type | Execution playbook |
| Workflow mode | IMPLEMENT (session sau) |
| RISK proposed | medium — Wyatt finalize (chạm `agent/`, `retrieval/`, `.claude/hooks/` — trong RISK_PATHS) |

> **Đọc trước khi run:** [ohana-ai/CLAUDE.md](../../CLAUDE.md) §3 (port table) + [spec 01](01-Task-OhanaAISeller-GD0.md) §5 (source inventory). Task này CHỈ thực thi Phase 1 — **KHÔNG** động Phase 2-5.

---

## §1 — Context (session sau)

**Bạn (session sau) đang ở đây:**
- CWD: `/Users/wyattngo/Sites/localhost/ohana-ai/`
- ADP v2.3 đã install (hooks + tools + tests, spine 190/191 pass)
- ADP:MANIFEST đã có trong CLAUDE.md §5
- `docs/tasks/01-*` = parent spec, `docs/tasks/02-*` = file này
- **KHÔNG có code**. `git status` sẽ fail vì chưa `git init`.

**Bạn KHÔNG được:**
- Fork nguyên `drnickv4/` repo (violates spec 01 §12)
- Copy `db/models.py` từ DrNick (single-tenant → viết lại tenant-first ở Phase 2)
- Port `bridge/onfa_client.py`, `tools/onfa_actions.py`, ConfirmEvent 2FA, financial pending logic
- Đè lên `ohana-ai/.claude/hooks/` (đã có ADP v2.3 — bổ sung, không clobber)

**Bạn CẦN:**
- Port list rõ ràng (spec 01 §3 Sub-task A) — clone chọn lọc, adapt, verify smoke.

---

## §2 — Goal

`ohana-ai/` chạy được `uvicorn app.main:app` (skeleton), pyproject.toml valid, `test_smoke.py` GREEN, git commit đầu tiên tag `phase-1-bootstrap`. KHÔNG có ONFA/money reference nào trong grep.

**Definition of Done đo được:**
1. `python -m pytest tests/test_smoke.py -x -q` → exit 0
2. `grep -rn "onfa_client\|onfa_actions\|pending_action\|2fa\|ConfirmEvent" ohana-ai/ --exclude-dir=.claude --exclude-dir=docs` → 0 hit
3. `uvicorn app.main:app --port 8001 --no-access-log` startup không exception (kill sau 3s)
4. `git log --oneline` có commit `phase-1-bootstrap`

---

## §3 — Scope

### IN scope (Phase 1 sub-tasks)

| Sub-phase | Nội dung |
|---|---|
| **1.0 Discovery** | Đọc drnickv4/ để xác nhận từng file trong port list tồn tại + version |
| **1.1 Skeleton** | git init, pyproject.toml, app/ FastAPI entry, tests/, .venv |
| **1.2 Port generic modules** | agent/llm_client, agent/embedder, agent/providers/, retrieval/, parsing/, storage/ |
| **1.3 Port .claude/ discipline** | guardrail.py (adapt R1.13), reviewer agent, CI workflow, Alembic skeleton — bổ sung vào .claude v2.3 sẵn có |

### OUT of scope (defer)

- `db/models.py` tenant-first (Phase 2)
- `auth/identity.py` JWT extension (Phase 2)
- `retrieval/` shop_id namespace scope (Phase 2 — port shell trước, wiring shop_id ở Phase 2)
- `bridge/ohana_client.py` (Phase 4)
- `agent/policy_gate.py` (Phase 5)
- `api/*.py` (Phase 3+)

---

## §4 — Safety gate

- ✅ **Priority (Ohana):** safety → trust → stability → growth
- ⚠️ **RISK:** medium. Chạm `agent/`, `retrieval/` = trong RISK_PATHS parent MANIFEST. Floor rule: cần reviewer gate + checkpoint stamp.
- 🚫 **Financial modules:** grep-check MUST show 0 hit trước checkpoint 1.3.
- 🚫 **Guardrail R1.13:** DrNick block money rule không apply Ohana → placeholder `intent-safety` (implement thực ở Phase 5).

---

## §5 — Source inventory (drnickv4/ @ main)

> **[UNVERIFIED]** flags = phải chạy PRE trước khi cassert. Đừng copy blind.

| Source (drnickv4/) | Target (ohana-ai/) | Verify command | State |
|---|---|---|---|
| `agent/llm_client.py` | `agent/llm_client.py` | `test -f drnickv4/agent/llm_client.py` | Expected exist |
| `agent/embedder.py` | `agent/embedder.py` | `test -f drnickv4/agent/embedder.py` | Expected exist |
| `agent/providers/` | `agent/providers/` | `test -d drnickv4/agent/providers && ls drnickv4/agent/providers/*.py` | Expected exist (sub-package của `agent/`, imports `from agent.providers import ...` — corrected from spec draft after PRE-108, PHASE1_DISCOVERY §CORRECTIONS C-1) |
| `retrieval/` | `retrieval/` | `test -d drnickv4/retrieval` | [UNVERIFIED] — Ohana Phase 2 sẽ wrap shop_id, Phase 1 chỉ port raw |
| `parsing/` | `parsing/` | `test -d drnickv4/parsing` | Expected exist |
| `storage/` | `storage/` | `test -d drnickv4/storage` | [UNVERIFIED] |
| `.claude/hooks/guardrail.py` | `.claude/hooks/guardrail.py` | `test -f drnickv4/.claude/hooks/guardrail.py` | [UNVERIFIED path — có thể ở `.claude/skills/` hoặc `hooks/`] |
| Reviewer subagent | `~/.claude/agents/<name>.md` | grep `.claude/agents/` in drnickv4 | [UNVERIFIED] — có thể user-level đã có |
| CI workflow | `.github/workflows/*.yml` | `ls drnickv4/.github/workflows/` | [UNVERIFIED] |
| Alembic skeleton | `alembic.ini` + `db/migrations/env.py` | `test -f drnickv4/alembic.ini` | [UNVERIFIED] |
| RULES doc | `docs/DRNICK_RULES_*` (parent has ref) | `find drnickv4 -name "*RULES*"` | Expected exist |

### SKIP explicitly (never copy)

- `bridge/onfa_client.py`
- `tools/onfa_actions.py` (any file with `onfa_actions`)
- `db/models.py` (rewrite Phase 2)
- Bất kỳ file nào có `pending_action`, `ConfirmEvent`, `2fa`, `wallet`, `transaction`, `balance`, `commission` trong tên
- `.env` / `.env.example` chứa ONFA credentials

---

## §6 — Pre-flight checks (binary VERIFY)

```
PRE-101: drnickv4/ working tree state.
  Command: cd /Users/wyattngo/Sites/localhost/drnickv4 \
         && git status --short \
         && git rev-parse --abbrev-ref HEAD \
         && git rev-parse HEAD
  Expected: working tree clean AND current branch = `main`. Ghi SHA vào PHASE1_DISCOVERY.md dưới key `DRNICKV4_PIN_SHA=<sha>`.
  If branch ≠ main: STOP — hỏi Wyatt trước khi checkout (đừng auto-checkout).
  If uncommitted: STOP — hỏi Wyatt, đừng auto-stash drnickv4.

PRE-102: db/models.py body (parent PRE-001).
  Command: grep -nE "shop_id|tenant_id|__tablename__" /Users/wyattngo/Sites/localhost/drnickv4/db/models.py
  Expected: liệt kê tables + kết luận có/không có scope column.
  Ghi kết quả vào docs/memory/PHASE1_DISCOVERY.md.
  If có shop_id sẵn: note cho Phase 2 (giảm scope rewrite).

PRE-103: Guardrail location.
  Command: find /Users/wyattngo/Sites/localhost/drnickv4/.claude -name "guardrail*" -type f
  Expected: chính xác 1 file path.
  If 0 hit: STOP — hỏi Wyatt (spec 01 §5 assumes tồn tại).
  If >1 hit: liệt kê, chọn file trong .claude/hooks/ (không phải skills/).

PRE-104: Reviewer subagent location.
  Command: ls /Users/wyattngo/Sites/localhost/drnickv4/.claude/agents/ 2>/dev/null
  Expected: có files hoặc empty (user-level default).
  If empty: skip port, dùng ~/.claude/agents/ đã có (6 v2.3 agents identical).

PRE-105: CI workflow.
  Command: ls /Users/wyattngo/Sites/localhost/drnickv4/.github/workflows/ 2>/dev/null
  Expected: liệt kê yml files.
  If empty: skip CI port, gắn "TODO Phase 1.4" vào KNOWN_ISSUES.

PRE-106: Alembic skeleton.
  Command: test -f /Users/wyattngo/Sites/localhost/drnickv4/alembic.ini && ls /Users/wyattngo/Sites/localhost/drnickv4/db/migrations/
  Expected: alembic.ini + env.py + versions/.
  If fail: dựng Alembic từ scratch (alembic init db/migrations).

PRE-107: Python version + deps + install pattern.
  Command:
    cat /Users/wyattngo/Sites/localhost/drnickv4/pyproject.toml
    grep -nE "requires-python|\[project\.optional-dependencies\]|\[dependency-groups\]" \
      /Users/wyattngo/Sites/localhost/drnickv4/pyproject.toml
    test -f /Users/wyattngo/Sites/localhost/drnickv4/requirements-dev.txt && echo "USES: requirements-dev.txt" || true
    test -f /Users/wyattngo/Sites/localhost/drnickv4/uv.lock && echo "USES: uv" || true
    test -f /Users/wyattngo/Sites/localhost/drnickv4/poetry.lock && echo "USES: poetry" || true
  Expected: xác định (a) Python version pin, (b) install pattern: `.[dev]` extra vs `dependency-groups` (PEP 735) vs uv/poetry vs requirements-dev.txt.
  Ghi vào docs/memory/PHASE1_DISCOVERY.md dưới `DRNICKV4_INSTALL_PATTERN=<pattern>`.
  Nếu drnickv4 dùng uv/poetry: sub-phase 1.1 step 4 phải adapt (`uv sync` / `poetry install`), KHÔNG blindly `pip install -e ".[dev]"`.

PRE-108: Grep ONFA references in port targets.
  Command: for f in agent/llm_client.py agent/embedder.py providers retrieval parsing storage; do
             echo "=== $f ==="
             grep -rn "onfa\|ONFA\|wallet\|pending_action\|ConfirmEvent" /Users/wyattngo/Sites/localhost/drnickv4/$f 2>/dev/null || echo "(clean)"
           done
  Expected: identify import lines cần strip sau khi copy.
  Log tất cả hit vào docs/memory/PHASE1_DISCOVERY.md.
```

**Rule:** Nếu bất kỳ PRE nào return unexpected → STOP+WAIT hỏi Wyatt. Không auto-fix.

---

## §7 — Execute steps

### Sub-phase 1.0 — Discovery (READ-ONLY)

<!-- ADP:PHASE 1.0 -->
STATUS: DONE
EVIDENCE: commit=ad562e0, gate_exit=0, duration=0s, review=skip(docs-only), ran=2026-07-16T22:48
GOAL: docs/memory/PHASE1_DISCOVERY.md ghi đầy đủ kết quả PRE-101..108 + version snapshot.
APPROACH: Run each PRE, capture output, không sửa gì trong drnickv4/.
ALLOWED_FILES: docs/memory/PHASE1_DISCOVERY.md
GATE: test -s docs/memory/PHASE1_DISCOVERY.md && grep -q "PRE-108" docs/memory/PHASE1_DISCOVERY.md
RETRY: 0/3
RISK: low
<!-- /ADP -->

**Steps:**
1. `mkdir -p docs/memory && touch docs/memory/PHASE1_DISCOVERY.md`
2. Run PRE-101..108, append kết quả vào file với markdown headers.
3. STOP+WAIT Wyatt review discovery report.

---

### Sub-phase 1.1 — Skeleton

<!-- ADP:PHASE 1.1 -->
STATUS: DONE
EVIDENCE: commit=b5b6b62, gate_exit=0, duration=6s, review=PASS(judge=APPROVE,model=output-evaluator@haiku,bound=474c15dc4640,tier=low), ran=2026-07-16T22:55
GOAL: git init + pyproject.toml + app/main.py FastAPI hello + tests/test_smoke.py RED trước, GREEN sau skeleton.
APPROACH: Copy pyproject.toml từ drnickv4 (dep list), strip financial deps (nếu có). FastAPI app/main.py chỉ có `/health`. test_smoke import app + assert `/health` returns 200.
ALLOWED_FILES: pyproject.toml, .python-version, .gitignore, app/__init__.py, app/main.py, tests/__init__.py, tests/test_smoke.py
GATE: .venv/bin/python -m pytest tests/test_smoke.py -x -q
REVIEW: PASS ref=docs/reviews/02-Task-Phase1-Bootstrap-Fork-DrNickV4-phase-1.1.json
RETRY: 0/3
RISK: low
<!-- /ADP -->

**Steps:**
1. `git init` + first commit `chore: init empty repo` (empty tree ok, sẽ có content ở step 2+)
2. Copy `drnickv4/pyproject.toml` → adapt name = `ohana-ai`, description mới. **STRIP** deps sau (grep-check):
   - Bất kỳ dep nào chỉ dùng cho ONFA bridge/2fa (nếu identify được ở PRE-108)
3. `.python-version` pin theo PRE-107.
4. `python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"` (hoặc theo cách drnickv4 install).
5. Viết `tests/test_smoke.py` **TRƯỚC** — assert `from app.main import app` + TestClient GET `/health` == 200. **Confirm RED**.
6. Viết `app/main.py` = FastAPI app tối thiểu + `/health`.
7. Re-run test → GREEN.
8. Commit `feat(phase-1.1): skeleton FastAPI + health + smoke test`
9. STOP+WAIT Wyatt.

---

### Sub-phase 1.2 — Port generic modules

<!-- ADP:PHASE 1.2 -->
STATUS: IN_PROGRESS
GOAL: 6 targets (2 files: agent/llm_client.py, agent/embedder.py · 4 packages: agent/providers/, retrieval/, parsing/, storage/) port sạch, mỗi target ZERO ONFA reference, test_ports.py phủ mỗi target 1 case.
APPROACH: **1 sub-checkpoint per target** (blame granularity, không batch). Loop: cp (file hoặc -R package) → strip imports theo PRE-108 → viết test case → chạy GATE_MODULE → commit → advance target kế (không chờ Wyatt confirm — RISK: medium theo §12 v2 override).
ALLOWED_FILES: agent/, retrieval/, parsing/, storage/, tests/test_ports.py
# GATE_MODULE (informational — executor chạy sau mỗi target trước khi commit; KHÔNG phải spine gate):
#   .venv/bin/python -m pytest tests/test_ports.py::test_<target>_imports_clean -x -q \
#     && ! grep -rnE "onfa|ONFA|wallet|pending_action|ConfirmEvent|2fa|balance|commission|transaction|deposit|withdraw" <target> | grep -v "^Binary"
GATE_FULL: .venv/bin/python -m pytest tests/test_ports.py tests/test_smoke.py -x -q
REVIEW: PASS ref=docs/reviews/02-Task-Phase1-Bootstrap-Fork-DrNickV4-phase-1.2.json
RETRY: 0/3
RISK: medium (chạm agent/, retrieval/ — trong RISK_PATHS)
<!-- /ADP -->

**Loop order (6 targets — file trước, sub-package sau, package to nhất cuối):**
1. `agent/llm_client.py`  (file — 1 hit `ConfirmEvent HALT` line 62 cần strip, xem PHASE1_DISCOVERY §PRE-108)
2. `agent/embedder.py`     (file — clean)
3. `agent/providers/`      (sub-package — copy `-R`; đảm bảo `agent/__init__.py` đã tồn tại từ target #1/#2 trước khi copy)
4. `retrieval/`            (package — clean)
5. `parsing/`              (package — clean)
6. `storage/`              (package — clean)

**Steps per target (loop 6 lần):**
1. `test_ports.py` RED trước: `from <target> import *` (files) hoặc `import <pkg>` (packages) không lỗi + grep-check `onfa|wallet|pending_action` = 0 hit.
2. Copy:
   - File: `cp /Users/wyattngo/Sites/localhost/drnickv4/<path>.py ./<path>.py` (đảm bảo parent dir tồn tại)
   - Package: `cp -R /Users/wyattngo/Sites/localhost/drnickv4/<pkg>/ ./<pkg>/`
3. Chạy PRE-108 grep local: log hit trong file mới copy.
4. Strip imports/comments ONFA-specific — commit từng target riêng.
5. Re-run test_ports + test_smoke → GREEN.
6. Commit `feat(phase-1.2): port <target>, strip ONFA refs (N lines)` — 1 checkpoint riêng (adp-checkpoint sau mỗi target)
7. Advance target kế (không dừng — §12 v2: RISK medium tự flip).

**Anti-patterns:**
- ❌ Copy retrieval/ và WIRE shop_id ngay (defer Phase 2).
- ❌ Copy DB session/models kèm với retrieval/ (chỉ port pgvector wrapper, session ở Phase 2).
- ❌ Fix bug drnickv4 phát hiện trong lúc port (log KNOWN_ISSUES, defer).

---

### Sub-phase 1.3 — Port .claude/ discipline + CI + Alembic

<!-- ADP:PHASE 1.3 -->
STATUS: TODO
GOAL: guardrail.py (adapt R1.13→intent-safety), reviewer agent verify, CI workflow, Alembic skeleton — bổ sung vào ohana-ai/.claude v2.3 sẵn có.
APPROACH: cp guardrail → adapt DENY rules → verify existing ADP v2.3 hooks không collide → CI workflow adapt project name → alembic init (nếu PRE-106 fail).
ALLOWED_FILES: .claude/hooks/guardrail.py, .github/workflows/, alembic.ini, db/migrations/, docs/RULES.md (adapt)
GATE (all-must-pass):
  1. python -c "import ast; ast.parse(open('.claude/hooks/guardrail.py').read())"       # guardrail parse OK
  2. echo '{}' | python .claude/hooks/guardrail.py                                       # guardrail smoke-run không crash
  3. python -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"   # CI yml parse OK
  4. .venv/bin/alembic -c alembic.ini current 2>&1 | grep -qE "current|head|INFO"       # alembic env.py loadable
  5. bash .claude/tools/adp-status.sh                                                    # ADP spine không hỏng sau khi thêm guardrail
RETRY: 0/3
RISK: medium (chạm .claude/hooks — cùng dir với ADP v2.3)
<!-- /ADP -->

**Steps:**
1. **Guardrail:**
   - Verify `.claude/hooks/guardrail.py` KHÔNG tồn tại trong ADP v2.3 install (đã check: 17 v2.3 hooks không có guardrail.py — safe to add).
   - `cp <PRE-103 path>/guardrail.py .claude/hooks/guardrail.py`
   - Edit R1.13 (money DENY) → placeholder comment `# R1.13-INTENT-SAFETY: implement Phase 5 policy_gate wiring`.
   - Adapt DENY paths: `bridge/onfa_*` không tồn tại Ohana → remove hoặc thay bằng `bridge/ohana_client.py` (Phase 4 target).
   - Test: py_compile guardrail.py + run headless với dummy hook JSON.
2. **Reviewer subagent:** theo PRE-104. Nếu ~/.claude/agents/ đã có 6 v2.3 → skip. Nếu drnickv4 có custom reviewer → note vào KNOWN_ISSUES.
3. **CI workflow:**
   - cp `.github/workflows/*.yml` per PRE-105.
   - Rename job names ONFA→Ohana, adapt Python version per PRE-107.
   - Adapt secrets refs (drop ONFA-specific).
4. **Alembic:**
   - Nếu PRE-106 PASS: cp alembic.ini + db/migrations/env.py + versions/ **rỗng** (không copy DrNick migrations).
   - Nếu FAIL: `.venv/bin/alembic init db/migrations` from scratch.
   - Đảm bảo env.py đọc DATABASE_URL từ ohana settings.
5. Commit từng bước riêng: `feat(phase-1.3a): port guardrail`, `feat(phase-1.3b): CI workflow`, `feat(phase-1.3c): alembic skeleton`.
6. Checkpoint 1.3 → advance tag ritual (không dừng chờ — §12 v2, RISK medium). Wyatt review async qua REVIEW_QUEUE.md.

---

## §8 — DB changes

**Không.** Phase 1 KHÔNG đụng schema. Alembic init empty tree — first migration ở Phase 2.

---

## §9 — i18n

N/A Phase 1.

---

## §10 — Post-checks (chạy trước khi tag `phase-1-bootstrap`)

```bash
# 1. Grep ONFA leaks (hard gate)
grep -rnE "onfa|ONFA|wallet|pending_action|ConfirmEvent|2fa|balance|commission|transaction|deposit|withdraw" \
  --exclude-dir=.git --exclude-dir=.claude --exclude-dir=docs --exclude-dir=.venv \
  /Users/wyattngo/Sites/localhost/ohana-ai/
# Expected: 0 hit STRICT (khớp §2 DoD #2 + §5 SKIP list). Nếu port cần giữ ref lịch sử, viết vào docs/memory/ (excluded), không giữ trong source.

# 2. Structure
python -c "from app.main import app; print(app.routes)"
# Expected: chỉ có /health

# 3. Smoke tests
.venv/bin/python -m pytest -q

# 4. Lint
ruff check . && ruff format --check .

# 5. Guardrail self-test
python .claude/hooks/guardrail.py --dry-run  # nếu có flag

# 6. ADP state
bash .claude/tools/adp-status.sh
# Expected: docs/tasks/02-* PHASE 1.0..1.3 DONE ×4 (nếu đã checkpoint)

# 7. Git log
git log --oneline
# Expected: ≥5 commits, cuối cùng có tag phase-1-bootstrap
```

---

## §11 — Deliverables

- `ohana-ai/` = git repo, first working tree.
- `pyproject.toml` + `.venv` + `.python-version`
- `app/main.py` (FastAPI hello)
- `agent/` (llm_client + embedder + providers/ sub-package), `retrieval/`, `parsing/`, `storage/` port clean
- `.claude/hooks/guardrail.py` co-exist với ADP v2.3 hooks (không clobber)
- `.github/workflows/` CI green
- `alembic.ini` + `db/migrations/env.py` (empty versions/)
- `docs/memory/PHASE1_DISCOVERY.md` — audit trail của PRE-101..108
- Git tag `phase-1-bootstrap` (executor tự tag sau 1.3 DONE — §12 v2 no-stop cho medium; Wyatt revert async nếu reject)
- `docs/tasks/02-*` PHASE 1.0..1.3 STATUS: DONE (qua adp-checkpoint.sh, không tự gõ)

---

## §12 — Constraints

- **STOP+WAIT chỉ khi `RISK: high`.** (Wyatt override 2026-07-16 — spec KHÔNG override DEC-019 tier semantics.)
  - Spine semantic (DEC-019, `.claude/tools/adp-checkpoint.sh:326`): `low` = auto-advance · `medium` = coder flip inline không cần chờ Wyatt confirm · `high` = per-step confirm + Wyatt sync diff review.
  - Phase 1 hiện tại đều là low/medium → executor tự flip STATUS: TODO → IN_PROGRESS sau mỗi checkpoint, không chờ ACK.
  - Nếu future phase gắn `RISK: high`, đây MỚI là điểm STOP+WAIT (per-step + sync diff review).
- **Batching per target trong 1.2 vẫn giữ 1-checkpoint-per-target** — không dừng chờ, nhưng vẫn commit riêng (blame + rollback granularity).
- **Additive/verify-first** — grep trước khi cp, không tin blindly spec 01 §5.
- **KHÔNG fix bug drnickv4** trong lúc port — log KNOWN_ISSUES, defer.
- **KHÔNG wire shop_id** vào retrieval/ ở Phase 1 (defer Phase 2).
- **KHÔNG copy db/models.py** (defer Phase 2 tenant-first rewrite).
- **Guardrail R1.13** → placeholder, KHÔNG implement logic thật (Phase 5).
- **DONE = adp-checkpoint.sh**, không self-certify. Retry cap = 3 → STOP + rollback + báo Wyatt.
- 1 sub-phase = 1 session (nếu compact) — resume qua adp-status.sh + PHASE1_DISCOVERY.md.

---

## §13 — Tracking

| Sub-phase | Concern | RISK proposed | STATUS | EVIDENCE |
|---|---|---|---|---|
| 1.0 | Discovery PRE-101..108 | low | TODO | — |
| 1.1 | Skeleton + smoke | low | TODO | — |
| 1.2 | Port 6 generic targets (2 files + 4 packages, incl. agent/providers/) | medium | TODO | — |
| 1.3 | .claude + CI + Alembic | medium | TODO | — |

> RISK proposed → Wyatt finalize trước khi bắt đầu 1.0. Floor rule: 1.2/1.3 chạm RISK_PATHS → tối thiểu medium.

---

## Session-sau checklist (đọc đầu tiên khi resume)

```
[ ] cd /Users/wyattngo/Sites/localhost/ohana-ai
[ ] Xác nhận CWD = ohana-ai (KHÔNG phải workspace root)
[ ] bash .claude/tools/adp-status.sh — xem PHASE 1.x nào TODO
[ ] Đọc docs/memory/PHASE1_DISCOVERY.md (nếu 1.0 xong)
[ ] Đọc docs/memory/KNOWN_ISSUES.md (nếu có)
[ ] Verify Wyatt đã finalize RISK tier (search "RISK: medium" trong file này)
[ ] Bắt đầu từ sub-phase TODO đầu tiên (không skip)
[ ] Sau mỗi sub-phase: bash .claude/tools/adp-checkpoint.sh — KHÔNG tự gõ DONE
```

---

## Assumptions & Open (cần Wyatt/session sau xác minh)

1. drnickv4/ có clean working tree (PRE-101).
2. `.claude/hooks/guardrail.py` tồn tại trong drnickv4 (PRE-103) — nếu là skill file cần adapt cách port khác.
3. Reviewer subagent user-level đã đủ (PRE-104) — không cần port custom.
4. drnickv4 dùng Alembic thật (PRE-106) — nếu dùng migration tool khác cần đổi approach.
5. Ohana AI dùng cùng LLM providers như DrNick (OpenAI + Anthropic + fallback). Nếu list khác → adapt providers/ sau port.
6. FastAPI framework choice khớp DrNick — không dùng Django/Flask.
