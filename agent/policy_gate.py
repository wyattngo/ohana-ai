"""Draft policy gate.

The MPV is human-in-the-loop: every generated reply is parked for seller review. Intent and
confidence remain in ``DraftContext`` because the next policy phase will use them to mark
ESCALATE, but neither can send a customer message.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

# Conservative default (spec §4 "gate là điều kiện ship, không optional"). Bumping this
# DOWN is an F3-scope change and must land as its own spec revision, not a config toggle.
DEFAULT_CONFIDENCE_THRESHOLD = 0.85

SENSITIVE_INTENTS: frozenset[str] = frozenset(
    {"complaint", "refund", "price_negotiation", "specific_order"}
)


@dataclass(frozen=True)
class DraftContext:
    confidence: float  # 0..1, the drafter's own self-reported confidence
    intent: str  # code — matched against SENSITIVE_INTENTS
    shop_auto_enabled_for_intent: bool  # shop-level opt-in for THIS intent


@dataclass(frozen=True)
class DraftDecision:
    action: Literal["auto_send", "park"]
    # stable code: park:sensitive_intent | park:low_confidence
    #            | park:auto_disabled_for_intent | send:within_policy
    reason: str


def decide(ctx: DraftContext, *, threshold: float = DEFAULT_CONFIDENCE_THRESHOLD) -> DraftDecision:
    if ctx.intent in SENSITIVE_INTENTS:
        return DraftDecision(action="park", reason="park:sensitive_intent")
    if ctx.confidence < threshold:
        return DraftDecision(action="park", reason="park:low_confidence")
    if not ctx.shop_auto_enabled_for_intent:
        return DraftDecision(action="park", reason="park:auto_disabled_for_intent")
    return DraftDecision(action="park", reason="park:manual_review_required")
