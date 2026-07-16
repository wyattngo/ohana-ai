"""Provider-agnostic embedding interface (tách khỏi LLMClient: embeddings ≠ chat).

Đổi provider (OpenAI → khác) = thêm adapter, KHÔNG sửa retrieval/agent core (§5.2).
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class Embedder(ABC):
    @abstractmethod
    async def embed(self, texts: list[str]) -> list[list[float]]:
        """Trả vector mỗi text (đúng thứ tự). Dim khớp column Embedding.embedding."""
        ...
