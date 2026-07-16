#!/bin/bash
# ============================================================
# ONFA Session End — Remind to update memory files
# ============================================================

set -eo pipefail

echo '{"continue": true, "additionalContext": "SESSION END CHECKLIST — Trước khi kết thúc session, update: (1) docs/memory/SESSION_LOG.md: thêm entry mới với branch, commits, files touched, issues found, decisions made, left off at. (2) docs/memory/KNOWN_ISSUES.md: thêm issues mới phát hiện hoặc đánh dấu FIXED. (3) docs/memory/DECISIONS.md: thêm decisions mới nếu có. (4) CLAUDE.md: nếu SESSION_LOG ghi CLAUDE.md update needed=yes, patch relevant section. (5) Skill CHANGELOG.md: nếu có lesson learned mới."}'
exit 0
