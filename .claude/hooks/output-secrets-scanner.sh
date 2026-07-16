#!/bin/bash
# =============================================================================
# Output Secrets Scanner — PostToolUse (ONFA port)
# Quét tool_response để bắt secret rò ra output. Warn-only mặc định.
# Bổ trợ pre-bash-guard/pre-edit-guard (vốn chỉ canh INPUT).
# Port từ claude-code-ultimate-guide examples/hooks/bash; sửa schema-drift +
# BSD-grep + bỏ false-positive bombs. Detect bằng python3 (convention ONFA).
#
# Wiring (settings.json PostToolUse, matcher "Bash|Read"):
#   .claude/hooks/output-secrets-scanner.sh
# Env tùy chọn:
#   OSS_BLOCK_ON_PRIVATE_KEY=1  -> phát hiện PEM/private key thì block (mặc định warn)
#   OSS_GENERIC=1               -> bật thêm generic key/secret/token (nhiễu hơn)
# =============================================================================
set -euo pipefail

INPUT=$(cat)

echo "$INPUT" | OSS_BLOCK="${OSS_BLOCK_ON_PRIVATE_KEY:-0}" OSS_GENERIC="${OSS_GENERIC:-0}" python3 -c '
import sys, json, re, os

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    data = {}

# Robust to schema drift: uu tien field output, fallback scan toan bo blob.
parts = []
for k in ("tool_response", "tool_output", "output"):
    v = data.get(k) if isinstance(data, dict) else None
    if v is not None:
        parts.append(v if isinstance(v, str) else json.dumps(v))
hay = "\n".join(parts) if parts else raw
if not hay.strip():
    sys.exit(0)

# High-precision patterns (da bo Azure{32,}, AWS-secret{40}, Heroku-UUID, generic broad)
PATTERNS = [
    ("Private Key (PEM)",      r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?(?:PRIVATE KEY|PRIVATE KEY BLOCK)-----"),
    ("Anthropic API Key",      r"sk-ant-[A-Za-z0-9_\-]{20,}"),
    ("OpenAI API Key",         r"sk-(?:proj-)?[A-Za-z0-9]{20,}"),
    ("AWS Access Key ID",      r"AKIA[0-9A-Z]{16}"),
    ("GCP API Key",            r"AIza[0-9A-Za-z_\-]{35}"),
    ("Stripe Key",             r"(?:sk|pk|rk)_(?:live|test)_[0-9a-zA-Z]{24,}"),
    ("Twilio Key",             r"SK[a-f0-9]{32}"),
    ("SendGrid Key",           r"SG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}"),
    ("Slack Token",            r"xox[baprs]-[0-9A-Za-z\-]{10,}"),
    ("GitHub Token",           r"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}"),
    ("GitLab Token",           r"glpat-[A-Za-z0-9_\-]{20,}"),
    ("NPM Token",              r"npm_[A-Za-z0-9]{36}"),
    ("PyPI Token",             r"pypi-[A-Za-z0-9_\-]{50,}"),
    ("JWT Token",              r"eyJ[A-Za-z0-9_\-]+\.eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"),
    ("DB URL w/ Password",     r"(?:postgres|postgresql|mysql|mongodb(?:\+srv)?)://[^:\s/]+:[^@\s]+@"),
    ("Redis URL w/ Password",  r"redis://:[^@\s]+@"),
]
if os.environ.get("OSS_GENERIC") == "1":
    PATTERNS.append(("Generic Secret",
        r"(?i)(?:api[_-]?key|apikey|secret|password|passwd|access[_-]?token|auth[_-]?token)\s*[:=]\s*[A-Za-z0-9/+_\-]{16,}"))

hits = []
for label, rx in PATTERNS:
    if re.search(rx, hay):
        hits.append(label)

if not hits:
    sys.exit(0)

types = ", ".join(sorted(set(hits)))
has_priv = any("Private Key" in h for h in hits)
msg = ("SECRET LEAK WARNING: nghi co secret ro trong output: " + types +
       ". KHONG commit/chia se output nay. Dung env var hoac secrets manager.")

# Khong in gia tri secret — chi in loai.
if has_priv and os.environ.get("OSS_BLOCK") == "1":
    print(json.dumps({"decision": "block", "reason": msg}))
else:
    print(json.dumps({"systemMessage": msg}))
' || true

exit 0
