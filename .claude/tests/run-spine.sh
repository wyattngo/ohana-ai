#!/bin/bash
# =============================================================================
# Spine-only entrypoint (Task#20 P5). Runs ONLY tests/spine/ (project-agnostic).
# For bootstrap self-test / fresh-machine verification — needs NO ONFA/DrNick.
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
source "$DIR/spine/cases.sh"
echo "──────────────────────────────────────────"
printf "RESULT: %s%d passed%s, %s%d failed%s\n" "$G" "$PASS" "$Z" "$([ "$FAIL" -gt 0 ] && echo "$R")" "$FAIL" "$Z"
[ "$FAIL" -eq 0 ]
