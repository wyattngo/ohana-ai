"""Spec 15 P1 gate — dead code removal invariants.

Purpose: prove `storage/*` and `tools.registry.{register, TOOLS}` are gone
after P1, while `Tool` dataclass survives (spec 13's DI drafter depends on it).

RED before P1: `import storage` succeeds, `tools.registry` still exposes
`register` and `TOOLS` — this file must fail. GREEN after deletion. If any
test here goes green BEFORE the deletion commit, P1 has not actually run;
if `test_registry_Tool_dataclass_kept` fails, P1 has over-deleted.
"""

from __future__ import annotations

import importlib

import pytest


def test_storage_module_removed() -> None:
    with pytest.raises(ModuleNotFoundError):
        importlib.import_module("storage")


def test_registry_register_removed() -> None:
    from tools import registry

    assert not hasattr(registry, "register"), (
        "tools.registry.register() is dead (0 caller — PRE-1502); spec 15 P1 must delete it"
    )


def test_registry_TOOLS_global_removed() -> None:
    from tools import registry

    assert not hasattr(registry, "TOOLS"), (
        "tools.registry.TOOLS global is dead (0 reader — PRE-1502); spec 15 P1 must delete it"
    )


def test_registry_Tool_dataclass_kept() -> None:
    # DI drafter (spec 13) + tool factories (shop_kb, ohana_read) import this.
    # Deletion here = P1 over-reached.
    from tools.registry import Tool  # noqa: F401
