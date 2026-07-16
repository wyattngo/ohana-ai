"""Local-disk Storage. Blocking IO chạy trong thread (asyncio.to_thread), không chặn event loop."""

from __future__ import annotations

import asyncio
from pathlib import Path

from storage.base import Storage


class LocalStorage(Storage):
    def __init__(self, root: str) -> None:
        self._root = Path(root).resolve()

    def _resolve(self, key: str) -> Path:
        # Defense-in-depth chống path traversal: path cuối phải nằm trong root.
        path = (self._root / key).resolve()
        if not path.is_relative_to(self._root):
            raise ValueError("path_traversal_blocked")
        return path

    def _write(self, path: Path, data: bytes) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    async def save(self, key: str, data: bytes) -> None:
        await asyncio.to_thread(self._write, self._resolve(key), data)

    async def load(self, key: str) -> bytes:
        return await asyncio.to_thread(self._resolve(key).read_bytes)
