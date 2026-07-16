#!/bin/bash
# =============================================================================
# Control-plane regression suite (P0).
# Codify các case đã chứng minh cho hooks/gates trọng yếu:
#   - output-secrets-scanner.sh   (PostToolUse secret-leak)
#   - mcp-config-integrity.sh     (SessionStart supply-chain)
#   - adp-checkpoint.sh judge gate (REVIEW: PASS ref= validation)
# Standalone · no network · dùng temp + env override (KHÔNG đụng ~/.claude.json thật).
# Exit != 0 nếu bất kỳ case fail (để wiring/CI gate được).
# Usage: bash .claude/tests/run.sh
# =============================================================================
set -uo pipefail

CLAUDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$CLAUDE_DIR/hooks"
TOOLS="$CLAUDE_DIR/tools"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Z=$'\033[0m'; else G=""; R=""; Z=""; fi
ok(){ PASS=$((PASS+1)); printf "  ${G}PASS${Z} %s\n" "$1"; }
no(){ FAIL=$((FAIL+1)); printf "  ${R}FAIL${Z} %s\n       %s\n" "$1" "$2"; }
has(){    case "$2" in *"$3"*) ok "$1";; *) no "$1" "phải chứa: [$3] | got: $2";; esac; }
hasnt(){  case "$2" in *"$3"*) no "$1" "KHÔNG được chứa: [$3] | got: $2";; *) ok "$1";; esac; }
empty(){ [ -z "$2" ] && ok "$1" || no "$1" "phải rỗng, got: $2"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "want [$3] got [$2]"; }

# ROOT_WS = control-plane repo root (hoisted from old [9] so spine cases that
# reference $ROOT_WS/docs work when spine runs standalone / before workspace).
ROOT_WS="$(cd "$CLAUDE_DIR/.." && pwd)"
