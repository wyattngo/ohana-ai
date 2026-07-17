"""Verified identity (R1.1 extended for multi-tenant).

`Identity(user_id, shop_id, role)` is the sole source of tenant scope. `shop_id` MUST
come from a signed JWT claim — never from a request body, header, or webhook payload
(the platform never trusts client-supplied tenancy). `verify_token` rejects tokens that
omit `shop_id` outright: there is no default fall-through, because "missing shop_id" is
indistinguishable from "attacker forged a token for a shop they don't own" if we allow one.

Algorithm is pinned to a literal list (HS256 for GĐ0 shared-secret dev flow; RS256 is a
Phase 3+ upgrade). Reading it from config would open the classic alg-confusion bypass.
"""

from __future__ import annotations

from dataclasses import dataclass

import jwt

_ALLOWED_ALGOS = ["HS256"]


@dataclass(frozen=True)
class Identity:
    user_id: str
    shop_id: str
    role: str


def verify_token(token: str, *, secret: str) -> Identity:
    """Verify an HS256 JWT and project it to Identity.

    Raises:
        jwt.InvalidSignatureError: signature mismatch (bad secret / tampered token).
        jwt.InvalidTokenError (or subclass): any other JWT decode failure.
        ValueError: token decoded but the `shop_id` claim is missing/empty. Also raised
            if `sub` or `role` are missing — no silent defaults for identity fields.
    """
    claims = jwt.decode(token, secret, algorithms=_ALLOWED_ALGOS)

    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        raise ValueError("invalid_sub — token missing 'sub' claim")

    shop_id = claims.get("shop_id")
    if not isinstance(shop_id, str) or not shop_id:
        raise ValueError("invalid_shop_id — token missing 'shop_id' claim")

    role = claims.get("role")
    if not isinstance(role, str) or not role:
        raise ValueError("invalid_role — token missing 'role' claim")

    return Identity(user_id=sub, shop_id=shop_id, role=role)
