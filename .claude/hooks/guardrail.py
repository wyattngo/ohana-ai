#!/usr/bin/env python3
"""
PreToolUse guardrail for Ohana AI Seller.

Enforces mechanically-checkable safety rules for the multi-tenant seller copilot.
Claude Code passes the pending tool call as JSON on stdin before it executes.

Adapted from drnickv4@d32b1c19 (2026-07-16 phase 1.3 port). DrNick-specific rules
dropped (R-NEW-4 2FA-client, R-NEW-13 money-from-memory); universal auth/secret/
CORS/prompt-injection rules retained. Phase 5 policy_gate will add Ohana intent-
safety rules (deferred — see docs/tasks/02 §7 Sub-phase 1.3 + spec 01 Phase 5).

Exit codes (Claude Code PreToolUse protocol):
    0 -> allow
    1 -> allow, but surface the warning text to Claude (heuristic hits)
    2 -> DENY the tool call (precise, security-critical hits)

Escape hatch (maps to the rulebook "break a rule -> document it"):
    put  `# guardrail: allow RULE_ID`  on the SAME line to bypass that one rule for that line.
    Then justify it in the PR / Verification Report KNOWN UNCOVERED section.

Tune the RULES table as the codebase grows. Keep it boring and readable on purpose.
"""

import json
import re
import sys

# Only inspect code actually being written/edited.
WATCH_TOOLS = {"Write", "Edit", "MultiEdit"}
CODE_SUFFIXES = (".py", ".js", ".jsx", ".ts", ".tsx")  # backend Python + seller-inbox FE JS/TS
VENDOR_DIRS = ("/vendor/",)  # minified 3rd-party bundles — never our code, skip to avoid noise

# (rule_id, severity, compiled_regex, message). severity: "deny" | "warn"
RULES = [
    (
        "R3_VERIFY_FALSE",
        "deny",
        re.compile(r"verify\s*=\s*False"),
        "Rule #3: HTTP client must not disable TLS verification (verify=False) in prod. "
        "Use verify=True / mTLS.",
    ),
    (
        "R1_TIER_HINT",
        "deny",
        re.compile(r"\btier_hint\b"),
        "Rule #1: tier/role must come from the verified auth context, never a client-supplied "
        "`tier_hint`. Multi-tenant: `shop_id` MUST come from the JWT, never the request body.",
    ),
    (
        "R1_TIER_FROM_BODY",
        "warn",
        re.compile(
            r"(request\.(json|form|args|data|get_json\(\))|\bbody\b|\bpayload\b|\bdata\b)"
            r"[^\n]{0,40}\[?['\"]?(tier|role|user_id|shop_id|seller_id|tenant_id)['\"]?",
            re.I,
        ),
        "Rule #1 (heuristic): looks like an identity/scope field (tier/role/user_id/shop_id/"
        "seller_id/tenant_id) is being read from the request body. Source it from the verified "
        "JWT / auth context instead — the multi-tenant scope MUST NOT come from the client.",
    ),
    (
        "R2_SECRET_EQ",
        "warn",
        re.compile(
            r"(secret|token|hmac|signature|\bsig\b|digest|api[_]?key|password|passwd|hash)"
            r"[^\n]{0,30}(==|!=)",
            re.I,
        ),
        "Rule #2 (heuristic): comparing a secret/token with ==/!=. "
        "Use hmac.compare_digest() for constant-time comparison.",
    ),
    (
        "SECRET_LEAK_KNOWN",
        "deny",
        re.compile(r"(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})"),
        "Secret leak: a hardcoded API key / credential was detected. "
        "Load it from env / secret manager.",
    ),
    (
        "SECRET_LEAK_ASSIGN",
        "warn",
        re.compile(
            r"(api[_]?key|secret|password|passwd|token)\s*=\s*['\"][^'\"]{16,}['\"]",
            re.I,
        ),
        "Possible hardcoded secret literal. If real, move it to env / secret manager.",
    ),
    # ---- v1.1 rules: web + prompt-injection surface ----
    (
        "R14_CORS_WILDCARD",
        "deny",
        re.compile(r"allow_origins\s*=\s*\[?\s*['\"]\*['\"]"),
        "R-NEW-14: CORS allow_origins=['*'] together with credentials is forbidden — the browser "
        "silently rejects it and breaks widget auth in prod. Use an explicit allow-list.",
    ),
    (
        "R7_PROMPT_INJECT",
        "warn",
        re.compile(r"f['\"][^'\"]*<[^>]+>\s*\{"),
        "R-NEW-7: a user-controlled field is interpolated straight into a prompt/XML tag. "
        "XML-escape via a safe-injection helper to prevent prompt-injection breakout.",
    ),
    # R-NEW-13 (money state from memory) and R-NEW-4 (client-trusted requires_2fa) intentionally
    # NOT ported — DrNick-specific concerns (money surface + 2FA gate). Ohana's intent-safety
    # gate is handled at Phase 5 policy_gate (auto-send blocking on sensitive intents like
    # complaint/refund/price_negotiation), not here. This hook stays code-level (secrets, CORS,
    # tier-from-body, prompt-injection); intent classification is a runtime concern.
    (
        "R7_1_LOG_FSTRING",
        "warn",  # Origin: strict rulebook R7.1
        re.compile(
            r"\blog(ger)?\.(debug|info|warning|warn|error|critical|exception)\s*\(\s*f['\"]"
        ),
        "R7.1: structured logging only. Pass key=value pairs "
        "(logger.info('event_name', user_id=uid)), never an f-string as the log message.",
    ),
    # ---- v1.2 rules: front-end origin-safety (seller inbox widget threat model) ----
    (
        "JS_ORIGIN_WILDCARD",
        "deny",
        re.compile(r"(postMessage\s*\([^)]*|targetOrigin\s*[:=]\s*)['\"]\*['\"]"),
        "JS origin wildcard: postMessage/targetOrigin to '*' leaks the message (incl. any auth "
        "token) to ANY origin. Pin the exact origin — seller inbox widget bridges MUST be origin-"
        "pinned.",
    ),
    (
        "JS_CORS_WILDCARD",
        "deny",
        re.compile(r"Access-Control-Allow-Origin['\"]?\s*[:,]\s*['\"]\*['\"]"),
        "JS CORS wildcard: Access-Control-Allow-Origin '*' with credentials is forbidden (same as "
        "R-NEW-14 on the Python side). Use an explicit allow-list.",
    ),
]

# Suppress obvious non-secrets for the assignment heuristic.
PLACEHOLDER = re.compile(
    r"(os\.(getenv|environ)|getenv|environ\[|<[^>]+>|your[-_]|x{3,}|placeholder|example|dummy|changeme)",
    re.I,
)


def _is_vendor(path):
    """Skip minified third-party bundles (web/vendor/**) — not our code, only noise."""
    norm = path.replace("\\", "/")
    return any(v in norm for v in VENDOR_DIRS)


def extract(tool_name, tool_input):
    """Return (file_path, content_being_written) for the watched tools."""
    fp = tool_input.get("file_path", "") or tool_input.get("path", "")
    if tool_name == "Write":
        return fp, tool_input.get("content", "")
    if tool_name == "Edit":
        return fp, tool_input.get("new_string", "")
    if tool_name == "MultiEdit":
        return fp, "\n".join(e.get("new_string", "") for e in tool_input.get("edits", []))
    return fp, ""


def scan(content):
    hits = []
    for lineno, line in enumerate(content.splitlines(), start=1):
        allowed = set(re.findall(r"guardrail:\s*allow\s+([A-Z0-9_]+)", line))
        for rid, sev, rx, msg in RULES:
            if rid in allowed:
                continue
            if not rx.search(line):
                continue
            if rid == "SECRET_LEAK_ASSIGN" and PLACEHOLDER.search(line):
                continue
            hits.append((sev, rid, lineno, msg, line.strip()))
    return hits


def scan_files(paths):
    """CI/headless mode: scan existing files. Exit non-zero only on DENY (warns are advisory).

    Reuses the same RULES + scan() as the PreToolUse hook — single source, no drift.
    """
    deny_total = 0
    warn_total = 0
    for path in paths:
        if not path.endswith(CODE_SUFFIXES) or _is_vendor(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                content = fh.read()
        except OSError:
            continue
        for sev, rid, lineno, msg, _src in scan(content):
            tag = "DENY" if sev == "deny" else "WARN"
            sys.stderr.write(f"{path}:{lineno} [{tag}] {rid}: {msg}\n")
            if sev == "deny":
                deny_total += 1
            else:
                warn_total += 1
    sys.stderr.write(f"guardrail: {len(paths)} path(s) — {deny_total} DENY, {warn_total} WARN\n")
    return deny_total


def main():
    # CI/headless mode: file paths as argv → scan them, fail (exit 1) on any DENY.
    if len(sys.argv) > 1:
        sys.exit(1 if scan_files(sys.argv[1:]) else 0)

    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except Exception:
        sys.exit(0)  # unparseable -> never block

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}
    if tool_name not in WATCH_TOOLS:
        sys.exit(0)

    fp, content = extract(tool_name, tool_input)
    if not fp.endswith(CODE_SUFFIXES) or _is_vendor(fp):
        sys.exit(0)

    hits = scan(content)
    if not hits:
        sys.exit(0)

    deny = [h for h in hits if h[0] == "deny"]
    lines = []
    for sev, rid, lineno, msg, src in hits:
        tag = "DENY" if sev == "deny" else "WARN"
        lines.append(f"  [{tag}] {rid} (line {lineno}): {msg}\n         > {src}")

    header = "Ohana guardrail BLOCKED this edit:" if deny else "Ohana guardrail warnings:"
    sys.stderr.write(header + "\n" + "\n".join(lines) + "\n")

    if deny:
        sys.stderr.write(
            "Fix the DENY items. To override a false positive, add "
            "`# guardrail: allow RULE_ID` on the line and justify it in the PR.\n"
        )
        sys.exit(2)
    sys.exit(1)


if __name__ == "__main__":
    main()
