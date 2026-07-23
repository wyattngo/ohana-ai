#!/usr/bin/env python3
"""roadmap-derive — gate the L1 derivation map against workflow anchors.

Pipeline (ADR 2026-07-22 derivation-pipeline):

    backend-workflow.md   (WHY + shape — anchors)
        |  derives
    ROADMAP.md §4.1.1     (work item + derives_from)

Two sub-commands:

    roadmap_derive.py verify    exit non-zero on dangling anchor / uncovered ID
    roadmap_derive.py derive    report gaps both ways (unused anchor, unmapped ID)

Wire `verify` into CI and pre-commit. A `derives_from` nobody gates is a link
that lies — the same failure mode `gen_codebase_map.py --check` exists to stop.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROADMAP_REL = "docs/ROADMAP.md"
WORKFLOW_REL = "docs/backend-workflow.md"
GATES_REL = "docs/gates"

# `<!-- anchor:w-7.1-webhook -->` — the immutable nail (ADR §5).
ANCHOR_RE = re.compile(r"<!--\s*anchor:([A-Za-z0-9._\-]+)\s*(?:redirect:[A-Za-z0-9._\-]+\s*)?-->")

# `| `GD0-INGEST` | `workflow#w-7.1-webhook` | note |` — cột 3 giữ `# weak-mapping`,
# nên PHẢI bắt cả nó; bỏ cột note là mất tín hiệu remap (bug đã dính 2026-07-22).
MAP_ROW_RE = re.compile(r"^\|\s*`(GD\d-[A-Z]+)`\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|?\s*$")

# `| `GD0-BOOTSTRAP` | Repo chạy… | … | internal | — |`
ID_ROW_RE = re.compile(r"^\|\s*`(GD\d-[A-Z]+)`\s*\|")

# `workflow#w-7.1-webhook` possibly wrapped in backticks.
REF_RE = re.compile(r"`?([a-z]+)#([A-Za-z0-9._\-]+)`?")

SCAFFOLD_RE = re.compile(r"n/a\s*\(scaffold\)", re.IGNORECASE)

# Section boundaries in ROADMAP.md.
SEC_41 = "### 4.1 "
SEC_411 = "#### 4.1.1"
SEC_41_END = "**Gate GĐ0"


@dataclass(frozen=True)
class Entry:
    """One row of the §4.1.1 derivation map."""

    work_id: str
    raw: str
    note: str = ""

    @property
    def is_scaffold(self) -> bool:
        return bool(SCAFFOLD_RE.search(self.raw))

    @property
    def is_weak(self) -> bool:
        return "weak-mapping" in self.note or "weak-mapping" in self.raw

    @property
    def ref(self) -> tuple[str, str] | None:
        """`(layer, anchor)` when the cell carries a real reference."""
        m = REF_RE.search(self.raw)
        return (m.group(1), m.group(2)) if m else None


def find_root(start: Path | None = None) -> Path:
    """Walk up until a directory holds docs/ROADMAP.md."""
    here = (start or Path(__file__).resolve().parent).resolve()
    for cand in (here, *here.parents):
        if (cand / ROADMAP_REL).is_file():
            return cand
    raise SystemExit(f"FATAL: không tìm thấy {ROADMAP_REL} từ {here} đi lên.")


def _slice(lines: list[str], start_pfx: str, end_pfx: str) -> list[str]:
    out: list[str] = []
    active = False
    for line in lines:
        if line.startswith(start_pfx):
            active = True
            continue
        if active and line.startswith(end_pfx):
            break
        if active:
            out.append(line)
    return out


def read_anchors(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    return set(ANCHOR_RE.findall(path.read_text(encoding="utf-8")))


def read_roadmap(root: Path) -> tuple[list[str], list[Entry]]:
    """Return (§4.1 declared IDs, §4.1.1 map entries)."""
    lines = (root / ROADMAP_REL).read_text(encoding="utf-8").splitlines()

    declared: list[str] = []
    for line in _slice(lines, SEC_41, SEC_411):
        m = ID_ROW_RE.match(line)
        if m:
            declared.append(m.group(1))

    entries: list[Entry] = []
    for line in _slice(lines, SEC_411, SEC_41_END):
        m = MAP_ROW_RE.match(line)
        if m:
            entries.append(Entry(work_id=m.group(1), raw=m.group(2), note=m.group(3)))

    return declared, entries


def resolve_layer(root: Path, layer: str) -> set[str] | None:
    """Anchors available for a layer, or None when the layer is unknown."""
    if layer == "workflow":
        return read_anchors(root / WORKFLOW_REL)
    if layer == "roadmap":
        return read_anchors(root / ROADMAP_REL)
    if layer == "gate":
        gates = root / GATES_REL
        if not gates.is_dir():
            return set()
        found: set[str] = set()
        for f in sorted(gates.glob("*.md")):
            found |= read_anchors(f)
        return found
    return None


def verify(root: Path) -> int:
    declared, entries = read_roadmap(root)
    mapped = {e.work_id: e for e in entries}
    problems: list[str] = []

    if not declared:
        problems.append(f"không đọc được ID nào ở §4.1 ({ROADMAP_REL}) — parser hỏng?")
    if not entries:
        problems.append(f"không đọc được dòng nào ở §4.1.1 ({ROADMAP_REL}) — parser hỏng?")

    # 1. Coverage — mọi ID khai ở §4.1 phải có mặt trong derivation map.
    for wid in declared:
        if wid not in mapped:
            problems.append(f"UNCOVERED  {wid}: khai ở §4.1 nhưng thiếu dòng ở §4.1.1")

    # 2. Map không được trỏ ID lạ (đánh máy sai / ID đã retire).
    for wid in mapped:
        if wid not in declared:
            problems.append(f"UNKNOWN-ID {wid}: có ở §4.1.1 nhưng không khai ở §4.1")

    # 3. Mỗi entry: scaffold miễn (ADR §5.1), còn lại phải resolve được anchor.
    for e in entries:
        if e.is_scaffold:
            continue
        ref = e.ref
        if ref is None:
            problems.append(f"UNRESOLVED {e.work_id}: derives_from trống ({e.raw!r})")
            continue
        layer, anchor = ref
        available = resolve_layer(root, layer)
        if available is None:
            problems.append(f"BAD-LAYER  {e.work_id}: layer '{layer}' không hợp lệ")
        elif anchor not in available:
            problems.append(f"DANGLING   {e.work_id}: {layer}#{anchor} — anchor không tồn tại")

    total = len(mapped)
    scaffold = sum(1 for e in entries if e.is_scaffold)
    anchored = total - scaffold

    if problems:
        print(f"verify_derives: FAIL ({len(problems)} vi phạm)")
        for p in problems:
            print(f"  ✗ {p}")
        print("\nDangling = khoá nối gãy. Sửa anchor hoặc derives_from trước khi commit.")
        return 1

    print(
        f"verify_derives: PASS — {total}/{len(declared)} ID có nguồn "
        f"({anchored} anchored, {scaffold} scaffold-exempt), 0 dangling"
    )
    return 0


def derive(root: Path) -> int:
    """Report gaps both directions. Advisory — never gates."""
    declared, entries = read_roadmap(root)
    mapped = {e.work_id: e for e in entries}

    wf_anchors = read_anchors(root / WORKFLOW_REL)
    used = {a for e in entries if (r := e.ref) is not None and r[0] == "workflow" for a in (r[1],)}

    def section(idx: int, title: str, items: list[str], empty: str) -> None:
        print(f"[{idx}] {title} ({len(items)}):")
        for it in items:
            print(f"  · {it}")
        if not items:
            print(f"  ({empty})")
        print()

    print("derive_roadmap — đề xuất diff (advisory, KHÔNG gate)\n")

    section(
        1,
        "Anchor workflow chưa ID nào neo vào",
        sorted(wf_anchors - used),
        "mọi anchor đều được dùng",
    )
    section(
        2, "ID §4.1 chưa có dòng ở §4.1.1", [w for w in declared if w not in mapped], "coverage đủ"
    )
    section(
        3,
        "Map tạm `# weak-mapping` — remap khi workflow tách sâu",
        [e.work_id for e in entries if e.is_weak],
        "không có",
    )

    # Đếm gate THẬT (GD0-STEP*.md), KHÔNG đếm README — không thì con số nói dối.
    gates = root / GATES_REL
    if gates.is_dir():
        files = sorted(gates.glob("GD0-STEP*.md"))
        unsigned = sum(1 for f in files if "approved_by: null" in f.read_text(encoding="utf-8"))
        state = f"{len(files)} gate · {unsigned} chưa ký"
    else:
        state = "CHƯA tồn tại (Session 4)"
    print(f"[4] Tầng gate: {state}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Gate the ROADMAP derivation map against workflow anchors."
    )
    ap.add_argument(
        "command",
        choices=("verify", "derive"),
        help="verify = gate (exit non-zero); derive = advisory report",
    )
    ap.add_argument("--root", help="repo root (default: search upward for docs/ROADMAP.md)")
    args = ap.parse_args()

    root = Path(args.root).resolve() if args.root else find_root()
    return verify(root) if args.command == "verify" else derive(root)


if __name__ == "__main__":
    sys.exit(main())
