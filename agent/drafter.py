"""Concrete `Drafter` — biến `(persona + history + message)` thành câu trả lời (spec 13 D0).

Đây là mảnh khuyết flag ở spec 11 §1.3: `agent.orchestrator.Drafter` là Protocol, và cho tới
giờ KHÔNG có impl nào — nên `api/webhook.py` không mount được, `build_persona_prompt` và
last-N history không có ai tiêu thụ. `LLMDrafter` lấp đúng chỗ đó.

**Structured output = một tool-loop với terminal tool `emit_reply` (approach C, spec 13 §2).**
Model được yêu cầu LUÔN kết thúc bằng `emit_reply(text, intent, confidence)`; args của tool
đó CHÍNH LÀ output có cấu trúc. Nhờ vậy `intent`+`confidence` đến từ LLM, KHÔNG phải hằng số
ta gán — một `confidence` bịa sẽ lái `policy_gate` auto_send bằng con số không có căn cứ.

**Ranh giới an toàn (import-graph, như `api/chat.py`).** Module này CHỈ sinh draft. Nó KHÔNG
import `agent.policy_gate`, `agent.orchestrator`, `channels.*`, hay `bridge.*sender*` — quyết
định gửi/park thuộc về orchestrator, không phải drafter. `tests/test_drafter.py` đi bao đóng
import để giữ ranh giới đó bằng CẤU TRÚC, không bằng lời dặn.

⚠️ **Hàm này KHÔNG chứng minh model không lộ danh tính.** Nó ráp prompt đúng và parse structured
đúng — việc model THẬT có tuân "không nói mình là AI" hay không phải đo bằng
`tests/test_drafter_live.py -m live` trên OUTPUT thật (cùng lý do `agent/persona.py:38`).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from agent.llm_client import AssistantStep, ChatMessage, LLMClient
from agent.persona import build_persona_prompt
from db.models import Message, Shop
from db.repos import ShopProfileRepo

# Tập mã intent TỐI THIỂU cho `policy_gate.decide` (spec 13 §1.2 — ranh giới với GD0-INTENT).
# BAO TRỌN 4 mã nhạy cảm của `agent.policy_gate.SENSITIVE_INTENTS` + một mã trung tính. KHÔNG
# import SENSITIVE_INTENTS vào đây: import `agent.policy_gate` phá gate ranh giới import-graph.
# Coupling giữ đồng bộ bằng test liên-module `test_emit_reply_enum_covers_sensitive_intents`
# (đỏ nếu policy_gate thêm mã nhạy cảm mà enum này không theo). GD0-INTENT sẽ mở rộng tập này
# thành 15 loại — đổi ở ĐÓ, không ở đây.
INTENT_CODES: tuple[str, ...] = (
    "general",
    "complaint",
    "refund",
    "price_negotiation",
    "specific_order",
)

# Tool bắt buộc: cách DUY NHẤT model kết thúc một lượt draft. `additionalProperties: False` chặn
# model nhét field lạ; `enum` ép `intent` vào tập máy hiểu (free-text "khiếu nại" ≠ `complaint`
# sẽ lọt gate âm thầm). `shop_id` KHÔNG bao giờ ở đây — nó tới từ tham số `draft()`, verified.
EMIT_REPLY_TOOL: dict[str, Any] = {
    "name": "emit_reply",
    "description": (
        "Phát ra câu trả lời cuối cùng cho khách kèm phân loại ý định và độ tự tin. "
        "LUÔN gọi tool này để kết thúc — đây là cách duy nhất để trả lời khách."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "text": {
                "type": "string",
                "description": "Câu trả lời gửi khách, bằng giọng của shop, tiếng Việt, 1-3 câu.",
            },
            "intent": {
                "type": "string",
                "enum": list(INTENT_CODES),
                "description": "Ý định của tin khách. Chọn mã sát nhất trong danh sách.",
            },
            "confidence": {
                "type": "number",
                "minimum": 0,
                "maximum": 1,
                "description": "Độ tự tin vào câu trả lời, 0..1. Không chắc thì để thấp.",
            },
        },
        "required": ["text", "intent", "confidence"],
        "additionalProperties": False,
    },
}


@dataclass(frozen=True)
class DraftResult:
    """Kết quả một lượt draft. Cấu trúc khớp `agent.orchestrator._Draft` (text/intent/confidence)
    để orchestrator tiêu thụ được mà drafter KHÔNG phải import orchestrator (gate ranh giới)."""

    text: str
    intent: str
    confidence: float


def _map_role(role: str) -> str:
    """Role của `Message` → role LLM. `seller` (shop tự trả) và `assistant` đều là phía shop."""
    if role == "user":
        return "user"
    return "assistant"


def _parse_emit_reply(step: AssistantStep) -> DraftResult:
    """Trích `DraftResult` từ tool_call `emit_reply`. KHÔNG có nó ⇒ raise, KHÔNG bịa.

    Trả về một draft với confidence mặc định khi model không gọi `emit_reply` chính là loại
    hỏng-âm-thầm spec này tồn tại để chặn: một con số bịa lái auto_send.
    """
    for tc in step.tool_calls:
        if tc.name != "emit_reply":
            continue
        args = tc.arguments
        try:
            text = str(args["text"]).strip()
            intent = str(args["intent"])
            confidence = float(args["confidence"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"emit_reply args không hợp lệ: {args!r}") from exc
        if not text:
            raise ValueError("emit_reply.text rỗng — không gửi bong bóng trống cho khách")
        if intent not in INTENT_CODES:
            raise ValueError(f"intent {intent!r} ngoài enum {INTENT_CODES}")
        if not 0.0 <= confidence <= 1.0:
            raise ValueError(f"confidence {confidence} ngoài [0,1]")
        return DraftResult(text=text, intent=intent, confidence=confidence)
    raise ValueError("model không gọi emit_reply — không sinh draft, không bịa confidence")


class LLMDrafter:
    """Sinh draft bằng LLM giọng shop + intent/confidence structured (spec 13 D0).

    D0 chưa offer grounding tool — model chỉ có `emit_reply`, một lượt. D1 thêm
    `lookup_size`/`lookup_shipping` vào cùng loop.
    """

    def __init__(
        self, llm: LLMClient, session_factory: async_sessionmaker[AsyncSession]
    ) -> None:
        self._llm = llm
        self._session_factory = session_factory

    async def draft(
        self, *, shop_id: str, customer_id: str, message: str, history: list[Message]
    ) -> DraftResult:
        """`(shop_id, customer_id, message, history)` → draft. `shop_id` đã verified upstream.

        `customer_id` chưa dùng ở D0 (đường tool D1 sẽ truyền nó xuống handler làm `user_id`).
        Giữ trong chữ ký vì Protocol `Drafter` khai nó và orchestrator gọi kèm.
        """
        system = await self._build_system_prompt(shop_id)
        messages: list[ChatMessage] = [{"role": "system", "content": system}]
        for m in history:
            messages.append({"role": _map_role(m.role), "content": m.content})
        messages.append({"role": "user", "content": message})

        step = await self._llm.step(messages, tools=[EMIT_REPLY_TOOL])
        return _parse_emit_reply(step)

    async def _build_system_prompt(self, shop_id: str) -> str:
        """Load `Shop.name` + `ShopProfile.persona_md` (scope theo `shop_id`) → persona prompt.

        Shop/profile thiếu ⇒ `build_persona_prompt` trả đoạn trung tính, KHÔNG raise: một shop
        chưa điền persona vẫn phải trả lời được khách, chỉ là bằng giọng chung.
        """
        async with self._session_factory() as session:
            shop = await session.get(Shop, shop_id)
            profile = await ShopProfileRepo(session, shop_scope=shop_id).get()
        display_name = shop.name if shop is not None else shop_id
        persona_md = profile.persona_md if profile is not None else None
        return build_persona_prompt(persona_md, shop_display_name=display_name)
