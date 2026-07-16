#!/bin/bash
# =============================================================================
# adp-profile-gen.sh — bootstrap a repo's ADP profile from its COMMITTED CLAUDE.md
# ADP:MANIFEST (single source of truth). Lets `docs/.adp-project-profile.json` stay
# gitignored (local-only) yet be REGENERABLE on a fresh clone / new machine — closing
# the "fresh clone has no profile" gap without committing config into fintech repos.
#
# Emits ONLY the gate-load-bearing fields (the ones the spine reads):
#   risk_paths  ← MANIFEST RISK_PATHS (split on comma)   [progress-guard, DoR, floor-rule]
#   gate_runner ← MANIFEST GATE_RUNNER                    [test-reviewer]
#   spec_dir    ← MANIFEST SPEC_DIR (default docs/tasks)  [senior, checkpoint]
#   executor_skill ← MANIFEST EXECUTOR_SKILL              [coder/bug-fixer]
#   skill_map   ← {default: executor_skill}               [adp_profile_skill]
#   checkpoint_prefix ← MANIFEST CHECKPOINT_PREFIX (default adp)
# Rich advisory fields (paths/conventions/stack) are NOT manifest-derivable — a hand-rich
# profile is preserved (create-if-missing). Use --force to regenerate the bootstrap subset.
#
# Usage: adp-profile-gen.sh <repo> [--force]
# =============================================================================
set -uo pipefail

_ADPTD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$_ADPTD/../hooks/adp-lib.sh"
[ -f "$LIB" ] || { echo "FATAL: adp-lib.sh not found" >&2; exit 1; }
# shellcheck source=../hooks/adp-lib.sh
source "$LIB"

repo="${1:-}"; force="${2:-}"
[ -n "$repo" ] || { echo "usage: adp-profile-gen.sh <repo> [--force]" >&2; exit 2; }
[ -f "$repo/CLAUDE.md" ] || { echo "FATAL: no CLAUDE.md (manifest source) in $repo" >&2; exit 1; }

prof=$(adp_profile_path "$repo")
if [ -f "$prof" ] && [ "$force" != "--force" ]; then
    echo "profile exists (use --force to regenerate bootstrap subset): $prof"
    exit 0
fi

RP=$(adp_manifest_get "$repo" RISK_PATHS)
GR=$(adp_manifest_get "$repo" GATE_RUNNER)
SD=$(adp_manifest_get "$repo" SPEC_DIR); SD=${SD:-docs/tasks}
EX=$(adp_manifest_get "$repo" EXECUTOR_SKILL)
CP=$(adp_manifest_get "$repo" CHECKPOINT_PREFIX); CP=${CP:-adp}
[ -n "$RP" ] || { echo "FATAL: MANIFEST has no RISK_PATHS in $repo/CLAUDE.md" >&2; exit 1; }

mkdir -p "$(dirname "$prof")" 2>/dev/null || true
ADP_HOME="$(cd "$_ADPTD/../.." && pwd)"
python3 - "$prof" "$(basename "$repo")" "$RP" "$GR" "$SD" "$EX" "$CP" "$ADP_HOME" <<'PY' || { echo "FATAL: emit failed" >&2; exit 1; }
import json, sys
out, name, rp, gr, sd, ex, cp, ah = sys.argv[1:9]
risk = [x.strip() for x in rp.split(",") if x.strip()]
prof = {
    "schema": "adp-project-profile/v1",
    "project": name,
    "adp_home": ah,
    "gate_runner": gr,
    "spec_dir": sd,
    "executor_skill": ex,
    "checkpoint_prefix": cp,
    "risk_paths": risk,
    "skill_map": {"default": ex},
    "_generated_from": "CLAUDE.md ADP:MANIFEST (bootstrap; rich fields paths/conventions/stack are hand-added, not manifest-derived)",
}
open(out, "w").write(json.dumps(prof, ensure_ascii=False, indent=2) + "\n")
print("generated:", out, "| risk_paths:", len(risk), "| executor:", ex)
PY
