#!/bin/bash
# =============================================================================
# adp-bootstrap.sh — zero-touch ADP setup for a project (Task #20 P2, ADP V2.3).
#
# One command replaces the manual SETUP checklist:
#   1. Fingerprint the project stack (php-ci3 / python / node / go).
#   2. Write an ADP:MANIFEST into the project CLAUDE.md (idempotent; skip if present).
#   3. adp-profile-gen.sh → docs/.adp-project-profile.json (incl. adp_home).
#   4. Idempotent JSON-merge of the 3 ADP hooks into ADP_HOME/.claude/settings.json
#      (never clobber existing hooks).
#   5. git init if the project is not a git work tree (diff-binding needs it).
#   6. Spine self-test (adp-lib sources, settings valid, profile valid) + summary.
#
# AMBIGUITY → DECISION, never a silent guess: an unknown stack writes a conformant
# adp-decision/v1 artifact (3 options, one recommended) and STOPs with exit 3.
#
# Usage:  bash adp-bootstrap.sh <project-dir>
# Env:    ADP_SETTINGS_FILE  override the settings.json target (default ADP_HOME/.claude/settings.json)
# Exit:   0 ok · 2 usage · 3 decision-required (unknown stack)
# =============================================================================
set -uo pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADP_HOME="$(cd "$_ADPTD/../.." && pwd)"
HOOKS_DIR="$ADP_HOME/.claude/hooks"
SETTINGS="${ADP_SETTINGS_FILE:-$ADP_HOME/.claude/settings.json}"

proj="${1:-}"
[ -n "$proj" ] || { echo "usage: adp-bootstrap.sh <project-dir>" >&2; exit 2; }
[ -d "$proj" ] || { echo "FATAL: not a directory: $proj" >&2; exit 2; }
proj="$(cd "$proj" && pwd)"
name="$(basename "$proj")"

echo "ADP bootstrap → $name"
echo "  ADP_HOME = $ADP_HOME"
echo "  settings = $SETTINGS"

# --- 1. fingerprint ----------------------------------------------------------
stack="" ; gate_runner="" ; risk_seed=""
if   [ -f "$proj/composer.json" ] || { [ -d "$proj/application" ] && [ -d "$proj/system" ]; }; then
  stack="php-ci3"; risk_seed="wallet, balance, transaction, commission, cron"
  if [ -f "$proj/tests/run-tests.sh" ]; then gate_runner="bash tests/run-tests.sh"; else gate_runner="php tests/run.php"; fi
elif [ -f "$proj/pyproject.toml" ] || [ -f "$proj/requirements.txt" ] || [ -f "$proj/setup.py" ]; then
  stack="python"; gate_runner="pytest -q -x"; risk_seed="payments, orchestrator, migrations, bridge, auth"
elif [ -f "$proj/package.json" ]; then
  stack="node"; risk_seed="payment, auth, migration"
  if grep -q '"test"' "$proj/package.json" 2>/dev/null; then gate_runner="npm test"; else gate_runner="vitest run"; fi
elif [ -f "$proj/go.mod" ]; then
  stack="go"; gate_runner="go test ./..."; risk_seed="payment, auth, migration"
fi

# --- unknown → DECISION + STOP (no silent guess) -----------------------------
if [ -z "$stack" ]; then
  echo "  stack = UNKNOWN → decision required (no silent setup)"
  mkdir -p "$proj/docs"
  DEC="$proj/docs/.adp-decision-pending.json"
  python3 - "$DEC" "$name" <<'PY'
import json, sys
out, name = sys.argv[1:3]
json.dump({
  "schema": "adp-decision/v1",
  "id": "D-setup-stack-"+name,
  "trigger": "setup",
  "context": "adp-bootstrap could not fingerprint the stack (no composer.json / pyproject / package.json / go.mod). A human must pick how to gate this project.",
  "options": [
    {"id":"A","title":"Declare the stack manually","approach":"Add an ADP:MANIFEST to CLAUDE.md with an explicit GATE_RUNNER + RISK_PATHS, then re-run bootstrap.","pros":["exact control of gate + risk surface"],"cons":["manual step"],"risk":"low","effort":"S","recommended":True},
    {"id":"B","title":"Generic no-skill project","approach":"Treat as generic: blank EXECUTOR_SKILL (generic-coder mode, P4) + hand-written RISK_PATHS; bootstrap writes a skeleton MANIFEST for review.","pros":["fast","works for bespoke stacks"],"cons":["coder runs under stricter gate; you must set RISK_PATHS"],"risk":"medium","effort":"M","recommended":False},
    {"id":"C","title":"Abort — add a code-gen skill first","approach":"Author a project skill (like ci3-code-generator) and a test runner, then bootstrap.","pros":["full anti-drift coder path"],"cons":["largest upfront effort"],"risk":"low","effort":"L","recommended":False}
  ],
  "chosen": None, "decided_by": None, "ts": None
}, open(out,"w"), ensure_ascii=False, indent=2)
print("  decision →", out)
PY
  echo "  STOP: resolve $DEC (set \"chosen\") then re-run. (exit 3)"
  exit 3
fi

echo "  stack = $stack | gate_runner = $gate_runner"

# --- 2. MANIFEST (idempotent) ------------------------------------------------
CLAUDE="$proj/CLAUDE.md"
if [ -f "$CLAUDE" ] && grep -q 'ADP:MANIFEST' "$CLAUDE"; then
  echo "  MANIFEST: already present (skip)"
else
  [ -f "$CLAUDE" ] || printf '# %s\n' "$name" > "$CLAUDE"
  {
    printf '\n<!-- ADP:MANIFEST -->\n'
    printf 'GATE_RUNNER: %s\n' "$gate_runner"
    printf 'RISK_PATHS: %s\n' "$risk_seed"
    printf 'SPEC_DIR: docs/tasks\n'
    printf 'EXECUTOR_SKILL: \n'
    printf 'CHECKPOINT_PREFIX: adp\n'
    printf '<!-- /ADP -->\n'
  } >> "$CLAUDE"
  echo "  MANIFEST: written (stack=$stack; review RISK_PATHS before trusting the financial gate)"
fi

# --- 3. profile --------------------------------------------------------------
bash "$_ADPTD/adp-profile-gen.sh" "$proj" --force >/dev/null 2>&1 \
  && echo "  profile: docs/.adp-project-profile.json" || echo "  profile: WARN gen failed"

# --- 4. idempotent settings merge -------------------------------------------
[ -f "$SETTINGS" ] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }
python3 - "$SETTINGS" "$HOOKS_DIR" <<'PY'
import json, sys, os
settings_path, hooks_dir = sys.argv[1:3]
try:
    s = json.load(open(settings_path))
except Exception:
    s = {}
s.setdefault("hooks", {})
# (event, matcher_or_None, script)
WANT = [
    ("PreToolUse",   "Agent",        "progress-guard.sh"),
    ("SubagentStop", None,           "gate-verdict.sh"),
    ("PreCompact",   "manual|auto",  "checkpoint-on-compact.sh"),
]
added = []
for event, matcher, script in WANT:
    arr = s["hooks"].setdefault(event, [])
    if any(script in (h.get("command","")) for blk in arr for h in blk.get("hooks", [])):
        continue  # already registered — no-clobber, idempotent
    blk = {"hooks": [{"type": "command", "command": os.path.join(hooks_dir, script), "timeout": 15}]}
    if matcher:
        blk = {"matcher": matcher, **blk}
    arr.append(blk)
    added.append(script)
if added:
    with open(settings_path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
print("  settings: merged", (", ".join(added) if added else "(already current — no change)"))
PY

# --- 5. git init -------------------------------------------------------------
if [ -d "$proj/.git" ]; then echo "  git: already a work tree"
else ( cd "$proj" && git init -q ) && echo "  git: initialized (diff-binding ready)" || echo "  git: WARN init failed"; fi

# --- 6. spine self-test ------------------------------------------------------
ST_OK=1
[ -f "$HOOKS_DIR/adp-lib.sh" ] && bash -c "source '$HOOKS_DIR/adp-lib.sh'" 2>/dev/null || ST_OK=0
python3 -c "import json;json.load(open('$SETTINGS'))" 2>/dev/null || ST_OK=0
python3 -c "import json;json.load(open('$proj/docs/.adp-project-profile.json'))" 2>/dev/null || ST_OK=0
# Spine suite installed + parseable. NOT executed here: the suite's own P2 case invokes
# this bootstrap, so running it inline would recurse. Run it post-install:
#   bash .claude/tests/run-spine.sh
SPINE="$ADP_HOME/.claude/tests/run-spine.sh"
if [ -x "$SPINE" ] && bash -n "$SPINE" 2>/dev/null; then
  echo "  self-test: spine suite installed + parseable → run it: bash $SPINE"
else
  echo "  self-test: note — run-spine.sh not found (older layout?)"
fi
[ "$ST_OK" = 1 ] && echo "  self-test: spine OK (adp-lib sources, settings+profile valid JSON)" || echo "  self-test: WARN — inspect above"

echo "DONE. Next: review RISK_PATHS in $CLAUDE, add an <!-- ADP:PHASE --> spec under docs/tasks/, restart the session so hooks load."
exit 0
