#!/bin/bash
# =============================================================================
# MCP Config Integrity — SessionStart (ONFA port)
# Chống CVE-2025-54135/54136 (tamper MCP config / backdoor sau khi approve).
# Hash ~/.claude.json vs baseline + soát nội dung mcpServers (cờ nguy hiểm,
# package chưa pin version, secret hardcode trong env, URL ngoài lạ).
# Port từ ccguide examples/hooks/bash/mcp-config-integrity.sh — sửa:
#   - sha256sum -> hashlib (macOS không có sha256sum, set -e làm hook chết câm)
#   - logic check external-URL (grep -q | grep) vốn dead -> parse JSON chuẩn
#   - unpinned-check thô báo nhầm config đã-pin -> match chính xác per-server
# Warn-only (exit 0). Detect bằng python3 (convention ONFA).
#
# Setup 1 lần (sau khi config hợp lệ):  bash .claude/hooks/mcp-config-integrity.sh --init
# Wiring (settings.json SessionStart):
#   .claude/hooks/mcp-config-integrity.sh
# Test override: MCP_CFG=<file> MCP_BASELINE=<file> bash ...
# =============================================================================
set -uo pipefail

python3 -c '
import os, sys, json, hashlib, re

mode = sys.argv[1] if len(sys.argv) > 1 else ""
home = os.path.expanduser("~")
cfg = os.environ.get("MCP_CFG") or os.path.join(home, ".claude.json")
baseline = os.environ.get("MCP_BASELINE") or os.path.join(home, ".claude", ".mcp-baseline.sha256")

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

if mode == "--init":
    if os.path.isfile(cfg):
        open(baseline, "w").write(sha256(cfg) + "\n")
        print("baseline updated:", baseline)
    else:
        print("no config at", cfg)
    sys.exit(0)

warnings = []
if os.path.isfile(cfg):
    cur = sha256(cfg)
    if os.path.isfile(baseline):
        base = ""
        try:
            base = open(baseline).read().split()[0]
        except Exception:
            pass
        if base and cur != base:
            warnings.append("~/.claude.json DOI so voi baseline — soat MCP server la. Hop le thi: bash .claude/hooks/mcp-config-integrity.sh --init")
    else:
        warnings.append("Chua co baseline MCP. Tao 1 lan: bash .claude/hooks/mcp-config-integrity.sh --init")

    try:
        data = json.load(open(cfg))
    except Exception:
        data = {}

    servers = {}
    if isinstance(data, dict):
        servers.update(data.get("mcpServers") or {})
        for proj in (data.get("projects") or {}).values():
            if isinstance(proj, dict):
                servers.update(proj.get("mcpServers") or {})

    for name, s in servers.items():
        if not isinstance(s, dict):
            continue
        args = [str(a) for a in (s.get("args") or [])]
        cmd = str(s.get("command", ""))
        joined = " ".join([cmd] + args)
        if re.search(r"--dangerous|--allow-write|--no-sandbox|--disable-sandbox", joined):
            warnings.append("MCP " + name + ": co co nguy hiem (--dangerous/--allow-write/--no-sandbox).")
        if "npx" in cmd or "npx" in args:
            for a in args:
                if a.startswith("-") or "/" in a or a.endswith(".js"):
                    continue
                if a.endswith("@latest"):
                    warnings.append("MCP " + name + ": dung @latest (" + a + ") — pin version cu the.")
                elif "@" not in a.lstrip("@") and re.match(r"^@?[A-Za-z0-9][\w.\-]*(/[\w.\-]+)?$", a):
                    warnings.append("MCP " + name + ": package npx CHUA pin version (" + a + ") — nen " + a + "@<version>.")
        env = s.get("env") or {}
        if isinstance(env, dict):
            for k, v in env.items():
                if re.search(r"(?i)(password|secret|token|api[_-]?key|private)", str(k)) and isinstance(v, str) and len(v) >= 12 and not v.startswith("${"):
                    warnings.append("MCP " + name + ": env " + str(k) + " co the la secret hardcode — dung ${ENV}.")
        for u in re.findall(r"https?://[^\s\"]+", joined):
            if not re.search(r"npmjs|registry\.npm|github\.com|githubusercontent", u):
                warnings.append("MCP " + name + ": URL ngoai (" + u + ") — xac minh nguon tin cay.")

proj_mcp = ".mcp.json"
if os.path.isfile(proj_mcp):
    raw = open(proj_mcp, encoding="utf-8", errors="ignore").read()
    if re.search(r"--dangerous|--allow-write|--no-sandbox", raw):
        warnings.append("Project .mcp.json: co co nguy hiem — coi chung supply-chain.")
    if re.search(r"\$\(|`[^`]+`|&&|\|\|", raw):
        warnings.append("Project .mcp.json: co ky tu shell ($( ` && ||) — soat command injection.")

if warnings:
    msg = "MCP INTEGRITY: " + " ".join("[!] " + w for w in warnings)
    print(json.dumps({"systemMessage": msg}))
' "${1:-}"

exit 0
