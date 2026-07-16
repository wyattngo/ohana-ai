#!/bin/bash
# =============================================================================
# Control-plane regression suite — ENTRYPOINT (Task#20 P5 split).
#   tests/lib.sh            shared helpers + counters + TMP/trap + ROOT_WS
#   tests/spine/cases.sh    PROJECT-AGNOSTIC cases (run on any stack / bare copy)
#   tests/workspace/cases.sh  ONFA/DrNick-coupled cases (this monorepo only)
# CHECK 7 (post-edit-checker.sh) invokes THIS file and greps ^RESULT: — keep that.
# Spine-only run = tests/run-spine.sh (bootstrap self-test / fresh machine).
# =============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
source "$DIR/spine/cases.sh"
# workspace/ = ONFA/DrNick-coupled; absent on a fresh machine / export bundle → skip
[ -f "$DIR/workspace/cases.sh" ] && source "$DIR/workspace/cases.sh"
echo "──────────────────────────────────────────"
printf "RESULT: %s%d passed%s, %s%d failed%s\n" "$G" "$PASS" "$Z" "$([ "$FAIL" -gt 0 ] && echo "$R")" "$FAIL" "$Z"
[ "$FAIL" -eq 0 ]
