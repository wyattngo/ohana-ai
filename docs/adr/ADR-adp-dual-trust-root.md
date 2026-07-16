# ADR — ADP v2 E15: Dual Independent Trust-Roots (DrNick)

- **Status:** ACCEPTED (2026-06-18, Wyatt) · closes spec #19 §2.8 E15
- **Scope:** drnickv4 only. ONFA CI parity = separate milestone (does NOT block v2 local).

## Context
The ADP v2 spine (gate-verdict + adp-checkpoint + diff-binding) is **trust-root #1**, but it
runs on **Wyatt's local machine**. A single trust-root has single points of failure:
- It can be force-shadowed (`ADP_FORCE_SHADOW=1`), disabled, or hit a machine-specific issue.
- The local checkpoint commits in the project repo, but "committed locally" ≠ "independently verified".

If the only gate is the local spine, a bad change that slips it (or runs with the spine off)
reaches `main` unverified. Defense-in-depth needs a **second, independent** verifier on
infrastructure the developer does not control.

## Decision
**Two independent trust-roots must BOTH be green for a DrNick change to reach `main`:**

| | Trust-root #1 — local ADP spine | Trust-root #2 — DrNick CI |
|---|---|---|
| Where | Wyatt's machine (Claude Code hooks) | GitHub Actions (`.github/workflows/ci.yml`) |
| Infra | local working tree | clean checkout + **real Postgres + Redis** services |
| Gate | `gate-verdict.sh` (RED-proof + diff-bound), `adp-checkpoint.sh` floor-rule + REVIEW gate | headless `guardrail.py` (DENY) · ruff · mypy strict · `check_drift.py` · **`pytest -q`** · vitest |
| Bypassable? | yes (`ADP_FORCE_SHADOW`, local) | **no** (independent infra, unbypassable per ci.yml) |
| Trusts the other? | no | no |

**Corroboration:** CI runs the SAME pytest suite as the ADP `gate_runner`
(`.venv/bin/python -m pytest -q -x`) but is **stricter, not merely equal** — and the difference is
the point:
- no `-x`, so CI runs *every* test (the local `-x` stops at the first failure);
- it stands up **real Postgres + Redis** service containers, so the DB/Redis tests run for real
  instead of skipping as they may on a local machine without those services;
- it re-runs `guardrail.py` headless over the whole source, plus ruff / mypy / `check_drift.py`.

**A green ADP checkpoint therefore does NOT guarantee a green CI** — CI can fail tests the local
gate skipped (infra) or never reached (`-x`). Neither root's PASS implies the other's; that
asymmetry is the defense-in-depth. A local checkpoint that CI later fails = a caught divergence
(local spine wrong / disabled / stale / infra-skipped) — exactly the false confidence the second
root exists to catch.

**Merge requirement (GitHub-side config, owned by Wyatt):** the `CI` workflow should be a
**required status check** on the protected branch (branch protection). That is the enforcement
point where trust-root #2 gates the merge — the local spine cannot satisfy it.

> **Enforcement status (2026-06-18): SIGNAL, not yet a hard gate.** `wyattngo/DrNickv4` is a
> PRIVATE repo on GitHub **Free**, where branch protection / rulesets are unavailable ("Upgrade
> to Pro or make public"). So the required-check **cannot be enforced mechanically yet**. What
> still holds: `ci.yml` runs on every push/PR and shows red/green on the PR — trust-root #2 is a
> visible SIGNAL, and "don't merge if CI is red" is a discipline. To make it a hard gate, either
> upgrade to GitHub Pro or make the repo public, then set the required check (+ grant the gh
> token the `Administration: write` permission). Until then this ADR's merge-gate is advisory.

## Consequences
**Good:** no single point of failure; CI is independent + unbypassable; the two roots
cross-check (local catches process violations like no-RED-proof that pytest can't; CI catches
machine-specific/spine-off escapes that the local gate can't).

**Boundary / not in scope:**
- **ONFA CI parity** — ONFA (`Localhost Onfa/`) has no equivalent independent CI yet; that is a
  separate milestone. v2 local (ONFA via the cwd-aware spine) is unaffected.
- The local spine cannot read CI status at checkpoint time (CI is async on push/PR). Corroboration
  happens at **merge** (required check), not at local checkpoint. The local checkpoint remains the
  per-phase gate; CI is the per-merge second gate.
- This ADR is guarded from drift by a control-plane assertion (`run.sh`): if `ci.yml` stops running
  the corroborating gate (`pytest` + `guardrail.py`), the suite flags it.
