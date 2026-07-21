"""General Chat — seller ↔ AI (spec 07 §7 Phase G1, Roadmap v4 §3.0 ưu tiên 1).

Seller đăng nhập hỏi AI câu hỏi tổng quát và nhận trả lời thật từ Together. Đây là lát cắt
ship được NGAY: nó không cần REST API của Tân (PRE-002), không cần wiki corpus (PRE-003),
không cần Zalo creds (PRE-004), không cần embedding.

**Ranh giới an toàn — lý do tồn tại của cách file này được viết.** Chat ở đây KHÔNG grounded:
không Wiki-RAG, không tồn kho thật, không đơn hàng thật. Nó CÓ THỂ bịa. Vì vậy nó tuyệt đối
không được đứng chung đường với luồng gửi tin cho khách hàng — nếu không, một câu bịa về giá
hay tồn kho sẽ đi thẳng tới khách thật.

Ranh giới đó được giữ bằng **cấu trúc**, không bằng lời dặn: module này không import
`agent.policy_gate`, `agent.orchestrator`, `channels.*`, `bridge.*sender*`, hay `PendingReply`
— và `tests/test_chat_endpoint.py` đi hết bao đóng import để bắt vi phạm, kể cả vi phạm gián
tiếp qua một helper trung gian. Muốn nối chat vào đường gửi khách thì phải làm đỏ một test có
tên nói rõ mình đang phá cái gì. Đó là chủ đích.

`grounded: false` trong response cũng phục vụ ranh giới đó: consumer nào đọc endpoint này
cũng thấy ngay đây là câu trả lời tự do, không phải câu có căn cứ.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Awaitable, Callable
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from agent.llm_client import LLMClient
from auth.identity import Identity

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = (
    "Bạn là trợ lý AI cho người bán hàng online tại Việt Nam. Trả lời ngắn gọn, thân thiện, "
    "bằng tiếng Việt. Bạn KHÔNG có quyền truy cập dữ liệu đơn hàng, tồn kho, hay giá thật của "
    "shop — nếu người dùng hỏi những thứ đó, hãy nói rõ bạn chưa tra cứu được và đề nghị họ "
    "kiểm tra trong hệ thống. Tuyệt đối không bịa số liệu."
)


class ChatIn(BaseModel):
    # `extra="ignore"` có chủ đích: client gửi kèm `shop_id` (hoặc bất cứ gì khác) thì field
    # đó bị BỎ QUA hoàn toàn, không có đường nào để nó ảnh hưởng tới xử lý. `shop_id` chỉ đến
    # từ JWT đã verify — đọc nó từ body là lỗ cross-tenant kinh điển (R1.22).
    model_config = ConfigDict(extra="ignore")

    message: str = Field(min_length=1, max_length=4000)


class ChatOut(BaseModel):
    reply: str
    model: str
    # Luôn False ở G1. Là field tường minh chứ không phải hằng số ẩn, để khi một phase sau
    # thêm Wiki-RAG grounding thì consumer phân biệt được hai loại câu trả lời — thay vì phải
    # đoán theo endpoint nào trả nó.
    grounded: bool = False
    usage: dict[str, int] = Field(default_factory=dict)


_client_cache: LLMClient | None = None


def get_llm_client() -> LLMClient:
    """FastAPI dependency — `TogetherClient` dựng LƯỜI, cache lại sau lần đầu.

    KHÔNG dựng ở module scope: SDK `openai` validate credentials ngay trong `AsyncOpenAI.
    __init__` (đã kiểm bằng test ở G0, `test_missing_key_fails_at_construction_not_at_call`),
    nên thiếu `TOGETHER_API_KEY` lúc import sẽ làm CẢ APP không boot — inbox, admin, health
    check chết theo, chỉ vì một endpoint chat chưa cấu hình. Dựng lười ⇒ hỏng đúng phạm vi:
    `/api/chat` trả 500, phần còn lại vẫn sống.

    Test override dependency này (`app.dependency_overrides`) nên không có request mạng nào
    trong suite.
    """
    global _client_cache
    if _client_cache is None:
        from agent.providers.together_client import TogetherClient

        # Spec 12 W0 (ISSUE-010): tiêm bộ đếm 429 làm `on_rate_limit`. Import TRONG hàm —
        # module-level `from app import alert_service` sẽ tái lập chính coupling mà G0 gỡ và
        # `test_openai_client_imports_without_alert_service` canh. Hook fire-and-forget, re-raise
        # `RateLimitError` nguyên vẹn (funnel `OpenAIClient._create`).
        from app import alert_service

        _client_cache = TogetherClient(on_rate_limit=alert_service.record_provider_429)
    return _client_cache


def build_router(
    # Sync hoặc async (spec 11 S1 làm nó async — tra `shops`). FastAPI nhận cả hai.
    identity_dep: Callable[..., Identity | Awaitable[Identity]],
    llm_dep: Callable[..., LLMClient] = get_llm_client,
) -> APIRouter:
    router = APIRouter(tags=["chat"])

    @router.post("/chat", response_model=ChatOut)
    async def chat(
        payload: ChatIn,
        identity: Identity = Depends(identity_dep),
        llm: LLMClient = Depends(llm_dep),
    ) -> ChatOut:
        messages: list[Any] = [
            {"role": "system", "content": _SYSTEM_PROMPT},
            {"role": "user", "content": payload.message},
        ]

        started = time.perf_counter()
        step = await llm.step(messages)
        latency_ms = int((time.perf_counter() - started) * 1000)

        usage = step.usage or {}
        model_id = getattr(llm, "_default_model", "unknown")

        # Đo lường là SỐ ĐẾM, không phải bản sao nội dung. Không log `payload.message` cũng
        # không log `step.content`: tin nhắn seller có thể chứa thông tin khách hàng, và PDPL
        # không cho ta rải nó vào log ứng dụng chỉ vì tiện debug. Cùng nguyên tắc đã áp cho
        # message lỗi của hook 429 ở G0.
        # `token_cached` = prompt-cache hit do PROVIDER báo (`agent/providers/openai_client.py`
        # `_extract_cache_hit_tokens` đọc được 3 shape: OpenAI/Together
        # `prompt_tokens_details.cached_tokens`, DeepSeek `prompt_cache_hit_tokens`, và fallback).
        # Đã được đo sẵn từ lúc port DrNick nhưng chưa ai ĐỌC.
        #
        # Log nó để trả lời bằng SỐ LIỆU, không bằng suy đoán, hai câu hỏi trước khi bàn tới
        # việc xây cache: (a) Together có tự cache prompt không, (b) tỷ lệ `token_cached/token_in`
        # là bao nhiêu. Hôm nay prompt ngắn (~134 token) nên gần như chắc chắn 0 — con số đáng
        # xem là SAU khi Wiki-RAG land, lúc prompt phình vì chunk wiki lặp lại giữa các request.
        # Đó mới là phần cache ăn được, và cũng là lúc quyết định xây cache mới có căn cứ.
        logger.info(
            "chat model=%s token_in=%s token_out=%s token_cached=%s latency_ms=%s shop_id=%s",
            model_id,
            usage.get("prompt_tokens", 0),
            usage.get("completion_tokens", 0),
            usage.get("cached_tokens", 0),
            latency_ms,
            identity.shop_id,
        )

        reply = (step.content or "").strip()
        if not reply:
            # Trả 200 kèm `reply: ""` là hỏng-âm-thầm: seller thấy một bong bóng chat trống,
            # không có lỗi nào, và không ai biết đã đốt token. Phát hiện thật (dò model G1
            # 2026-07-19): model **reasoning** (gpt-oss, GLM-5.2, Kimi) đẩy toàn bộ output
            # sang kênh suy luận và trả `content` rỗng khi `max_tokens` không đủ chỗ —
            # Kimi-K2.6 đốt sạch 300 token vẫn rỗng. Default hiện tại là non-reasoning nên
            # không dính, nhưng `TOGETHER_MODEL` đổi được bằng env: hàng rào này phải nằm ở
            # code, không nằm ở việc nhớ chọn đúng model.
            logger.warning(
                "chat empty_content model=%s token_in=%s token_out=%s shop_id=%s",
                model_id,
                usage.get("prompt_tokens", 0),
                usage.get("completion_tokens", 0),
                identity.shop_id,
            )
            raise HTTPException(status_code=502, detail="llm_empty_response")

        return ChatOut(
            reply=reply,
            model=model_id,
            grounded=False,
            usage=usage,
        )

    return router
