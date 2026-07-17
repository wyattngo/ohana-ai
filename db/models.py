"""ORM models — tenant-first schema (spec 01 §3 Sub-task B, §8).

Every row-owning table carries a `shop_id` (Text). Cross-shop leakage is prevented at the
query layer by requiring shop scope on every SELECT (retrieval/pgvector.py enforces it for
vector search; other repos will follow the same shape when they land). The tenant-isolation
gate in tests/test_tenant_isolation.py is the contract.

GĐ0 lands only the tables the Phase 2 gate exercises: `messages`, `embeddings`. The wider
schema (shops, sellers, customers, conversations, pending_reply) lands in Phase 5 alongside
the copilot/policy_gate work — keeping this migration to one concern (R1.10, R6 db pair).
"""

from __future__ import annotations

from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import BigInteger, DateTime, Index, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

_EMBED_DIM = 1536


class Base(DeclarativeBase):
    """Declarative base; alembic autogenerate targets `Base.metadata`."""


class Message(Base):
    """A message in a customer conversation (inbound customer OR seller reply OR drafted).

    `shop_id` is the tenant scope — never derived from client input, always from a verified
    JWT (auth.identity.verify_token). Cross-shop reads MUST include `WHERE shop_id = :scope`
    at the SQL level; post-filter is an R1.22 breach.
    """

    __tablename__ = "messages"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_id: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(Text, nullable=False)  # user | assistant | seller | system
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (Index("idx_msg_shop_created", "shop_id", "created_at"),)


class Embedding(Base):
    """Vector chunk. `namespace` scopes by kind (chat | platform_wiki | file:{id} …);
    `shop_id` scopes by tenant. Retrieval must filter on BOTH — namespace decides where to
    look, shop_id decides whose rows are eligible. `platform_wiki` is the only shared
    namespace and even then the shop scope still applies to per-shop wiki extensions.
    """

    __tablename__ = "embeddings"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_id: Mapped[str] = mapped_column(Text, nullable=False)
    namespace: Mapped[str] = mapped_column(Text, nullable=False)
    source_ref: Mapped[str | None] = mapped_column(Text, nullable=True)
    chunk: Mapped[str] = mapped_column(Text, nullable=False)
    embedding: Mapped[list[float]] = mapped_column(Vector(_EMBED_DIM), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    __table_args__ = (Index("idx_emb_shop_ns", "shop_id", "namespace"),)
