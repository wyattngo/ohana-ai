"""Tool registry + dispatch shape — single source of truth for the agent's tools.

Ported from drnickv4 with the R1.1 signature widened for multi-tenant: a handler receives
`(user_id, shop_id, args)` — `user_id` AND `shop_id` are separate args the orchestrator
supplies from a verified `auth.identity.Identity`; neither can appear in `parameters`, so
the LLM cannot direct a tool at another user or another shop.

Phase 3 lands the shape + Wiki RAG tool. Phase 4/5 populate F2 read tools + F3 write tools.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any, Literal

ToolHandler = Callable[[str, str, dict[str, Any]], Awaitable[dict[str, Any]]]


@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    parameters: dict[str, Any]  # JSON schema — feeds the LLM tools= param AND input validation
    handler: ToolHandler  # async (user_id, shop_id, args) -> {"success": bool, ...}
    kind: Literal["read", "action"] = "read"  # READ runs directly; ACTION → policy_gate (Phase 5)


TOOLS: dict[str, Tool] = {}


def register(tools: list[Tool]) -> None:
    """Add tools to the registry (app-startup wiring). Same name → overwrite (idempotent boot)."""
    for t in tools:
        TOOLS[t.name] = t
