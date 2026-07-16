# ADP v2 — Main Operating Prompt (thin, state-driven)

> This is the MAIN loop's operating contract for the role-specialized multi-agent
> pipeline (spec `docs/tasks/19-Task-ADP-v2-MultiAgent-Pipeline.md`). Keep it thin:
> the main loop **orchestrates state**, it does not implement. Authority lives in the
> deterministic spine (test exit code + diff-binding + hooks), NEVER in any agent.

## 0. Trust model (bất biến)
- **Deterministic spine = trust-root.** Quyền tick một micro-task PASS = hook
  `gate-verdict.sh` (test exit 0 + `adp_task_diff_sha` bound). Quyền tick một phase
  DONE = `adp-checkpoint.sh` trong project repo. KHÔNG agent nào (kể cả
  test-reviewer) được tự khai PASS/DONE.
- **Agents = advisor/producer.** Main spawns them, reads their factual report, lets
  the spine decide.

## 1. State substrate (single-writer — fix #2/#3)
| File | Writer | Readers | Purpose |
|---|---|---|---|
| `<repo>/docs/.adp-exec-state.json` | **MAIN only** | hooks (P3/P4) | current_agent + task_id + handoff, written BEFORE each spawn |
| `<repo>/docs/.adp-audit.jsonl` | hooks (`adp_audit_event`) | reports | append-only source-of-truth |
| `<root>/docs/tasks/NN-*.md` (sprint-spec) | senior (until frozen) | all | the plan; STATUS/EVIDENCE mutated only via checkpoint |
| `<repo>/docs/.sprint-spec.lock` | freeze step (`adp_spec_lock_write`) | checkpoint | E10 change-control hash |
| `<repo>/docs/.adp-project-profile.json` | project owner | all agents | E11 skill-map / RISK_PATHS / gate_runner |

One writer per file. Never let two roles write the same file.

## 2. Pre-spawn ritual (MAIN, every micro-task) — refuse-spawn gate
For each micro-task from the tech-lead brief, BEFORE calling the `Agent` tool:
1. Build a handoff JSON conforming to **`adp-handoff/v1`** (see §3).
2. `bash -c 'source .claude/hooks/adp-lib.sh; adp_exec_state_write "<repo>" "<handoff.json>"'`
   - This validates the handoff (E1) **and** asserts cwd is a git repo (FIX H).
   - Echo `OK` (rc0) → proceed to spawn. Any other output / rc1 → **DO NOT SPAWN**;
     fix the handoff or STOP. (Missing field / non-git cwd are refuse-spawn faults.)
3. Spawn the role agent (`coder` / `bug-fixer` / `test-reviewer` / …) with
   **`cwd` = the project repo** (FIX H — never the workspace root; root is non-git,
   diff-binding would be empty and the gate would silently pass).

## 3. Handoff schema — `adp-handoff/v1` (E1, KEYSTONE)
Every required field; the validator (`adp_handoff_validate`) refuses if any is
missing/empty. E3 (idempotency) and E7 (DoR) compose as fields on this object.
```json
{
  "schema": "adp-handoff/v1",
  "task_id": "P2.t3",
  "current_agent": "coder",
  "files": ["application/controllers/Foo.php"],
  "acceptance_cmd": "php tests/Foo_test.php",
  "risk_tier": "low",
  "parent_phase": "2",
  "blast": "single controller, no RISK_PATHS overlap",
  "attempt": 1
}
```
- `files` = per-task diff scope (FIX C); the SubagentStop gate binds the verdict to
  `adp_task_diff_sha` over exactly these paths and flags `diff ⊄ files`.
- `risk_tier` ∈ {high, medium, low}; floor rule: `files ∩ RISK_PATHS ⇒ ≥ medium`.
- `attempt` (optional, default 1) feeds E3 early-trip (same-diff-same-FAIL → trip@2).

## 4. CWD discipline (FIX H — hard rule)
- **Every exec-loop spawn ⇒ `cwd` = a project repo that is a git work tree**
  (`Localhost Onfa/` or `drnickv4/`). The root session edits ONLY `.claude/` and
  control-plane `docs/`.
- `adp_assert_git_repo "<repo>"` must pass before any spawn. Non-git cwd = silent
  diff-binding failure → refuse.

## 5. Project profile (E11) — agents read, never bake
Agents resolve project specifics (skill-map, RISK_PATHS, gate_runner, paths,
conventions) from `./docs/.adp-project-profile.json` (their cwd = project repo).
One agent definition serves every project; no ONFA path is hard-coded into an
agent. Map a task to its skill with `adp_profile_skill "<repo>" "<task_kind>"`.

## 6. Phase advance & change-control
- A phase advances only when EVERY micro-task PASS (spine), then
  `adp-review.sh stamp` + `adp-checkpoint.sh` in the project repo (phase-bridge, §2.6).
- Before checkpoint: `adp_spec_lock_verify "<repo>" "<spec_file>"` — DRIFT (frozen
  contract changed mid-sprint) ⇒ REFUSE (E10).
- Control-plane spec (workspace root, non-git) is **suite-gated** (`run.sh`), not
  adp-checkpoint — STATUS/EVIDENCE flipped directly after the suite is green.

## 7. Never (permanent)
Remote-publish of commits, branch integration, schema-change scripts, environment
rollout, auto-advancing a RISK:high phase without Wyatt's signed human artifact —
all out of every agent's and the loop's authority. STOP+WAIT before any micro-task
touching wallet / balance / transaction / commission / cron funds.
