"""Storage interface — mọi backend (local/S3) thỏa cái này (swap không sửa caller)."""

from __future__ import annotations

from abc import ABC, abstractmethod


class Storage(ABC):
    @abstractmethod
    async def save(self, key: str, data: bytes) -> None:
        """Ghi `data` dưới `key` (đè nếu trùng). `key` là opaque, do caller sinh (uuid)."""
        ...

    @abstractmethod
    async def load(self, key: str) -> bytes:
        """Đọc nội dung theo `key`. FileNotFoundError nếu không tồn tại."""
        ...
