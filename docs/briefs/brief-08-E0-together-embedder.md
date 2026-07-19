# BRIEF — Spec 08 Phase E0 · `TogetherEmbedder` + query/passage split

> **Executor:** `drnick-coder` (EXECUTOR_SKILL) · **Spec:** `docs/tasks/08-Task-OhanaAISeller-EmbedderSwap-E5.md` §7 Phase E0
> **Trạng thái brief:** SẴN SÀNG CHẠY — `RISK: medium` **đã ký** (Wyatt, 2026-07-19).
> Medium ⇒ 1 lần confirm tại **ANCHOR** (bước 5) + reviewer gate + auto-checkpoint + async `REVIEW_QUEUE.md`. KHÔNG per-step confirm.
>
> ⚠️ **Quy tắc brief này tuân theo (ISSUE-012):** mọi phần scope dưới đây là **TRÍCH NGUYÊN VĂN** từ spec, đặt trong blockquote. Phần tôi viết thêm là *bối cảnh* và *audit on-disk*, tách riêng, KHÔNG diễn giải lại scope. Nếu brief và spec lệch nhau ⇒ **spec đúng**, brief sai.

---

## 1. Phase block — trích nguyên văn từ spec §7

```
<!-- ADP:PHASE E0 -->
STATUS: TODO
ROADMAP: GD0-EMBED
GOAL: `TogetherEmbedder` gọi được e5 thật (1024-dim), prefix `query:`/`passage:` đặt ĐÚNG bên; `Embedder` ABC có `embed_query`/`embed_documents` với default delegate ⇒ `OpenAIEmbedder` + `_DeterministicDevEmbedder` KHÔNG vỡ; gate BẤT ĐỐI XỨNG đỏ khi prefix lệch bên.
APPROACH: ABC thêm 2 concrete method (KHÔNG abstract — thêm abstract sẽ phá mọi impl hiện có). `TogetherEmbedder` bám shape `together_client.py` spec 07 G0: base_url hằng số, model/key từ `Settings`, resolve model bằng `.strip() or DEFAULT` để chuỗi rỗng không trượt sang provider khác (đúng bug 2026-07-19). Call-site (`ingest.py`/`wiki.py`) chuyển sang `embed_documents`/`embed_query` — prefix là việc của ADAPTER, không phải của call-site, vì OpenAI không dùng prefix.
ALLOWED_FILES: agent/embedder.py, agent/providers/together_embedder.py, app/config.py, parsing/ingest.py, tools/wiki.py, tests/test_together_embedder.py, docs/reviews/, docs/smokes/, docs/tasks/08-Task-OhanaAISeller-EmbedderSwap-E5.md
GATE: .venv/bin/python -m pytest tests/test_together_embedder.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (proposed — ALLOWED_FILES KHÔNG giao RISK_PATHS ⇒ floor là low; đề xuất nâng lên medium theo tiền lệ spec 07 G0, vì đây là adapter provider mới + đổi ABC dùng chung. Wyatt chốt.)
BLOCKED_BY: PRE-E01 ✅
SMOKE: (điền khi chạy — có mặt runtime: gọi e5 thật)
<!-- /ADP -->
```

## 2. Execute steps — trích nguyên văn từ spec §7

> 1. `tests/test_together_embedder.py` (RED): (a) `TogetherEmbedder` là `Embedder`; (b) trỏ base_url Together, model/key từ `Settings`, KHÔNG hardcode; (c) `TOGETHER_EMBED_MODEL` rỗng ⇒ rơi về default, KHÔNG rơi sang model provider khác; (d) `embed_query` gắn `query: `, `embed_documents` gắn `passage: ` — kiểm bằng fake client bắt được text GỬI ĐI; (e) **gate bất đối xứng**: prefix không được hoán đổi/thiếu một bên; (f) `OpenAIEmbedder` + `_DeterministicDevEmbedder` vẫn thoả ABC sau khi thêm method (không vỡ impl cũ); (g) key KHÔNG lộ qua `repr()`.
> 2. `agent/embedder.py`: thêm 2 concrete method + docstring nói rõ vì sao default là delegate.
> 3. `agent/providers/together_embedder.py` + `app/config.py` 2 field.
> 4. `parsing/ingest.py` → `embed_documents`; `tools/wiki.py` → `embed_query`.
> 5. **STOP+WAIT** (ANCHOR).

Field config cần thêm — trích spec §6:

> - `app/config.py` += `together_embed_model` (default `intfloat/multilingual-e5-large-instruct`) + `DEFAULT_TOGETHER_EMBED_MODEL` + `EMBED_DIM` hằng số dùng chung.

---

## 3. Audit on-disk (tôi đọc code thật, 2026-07-19 — KHÔNG phải trích spec)

Phần này để executor không phải dò lại. Nếu lệch với thực tế lúc chạy ⇒ tin code, báo lại.

**`agent/embedder.py` hiện tại — 16 dòng, ABC một method:**
```python
class Embedder(ABC):
    @abstractmethod
    async def embed(self, texts: list[str]) -> list[list[float]]: ...
```
⇒ Thêm `embed_query` / `embed_documents` dạng **concrete delegate về `embed()`** thì `OpenAIEmbedder` và `_DeterministicDevEmbedder` không cần sửa một dòng. Đó chính là lý do spec cấm dùng `@abstractmethod`.

**3 call-site của `.embed(` (đã grep toàn repo, trừ test):**
| File | Dòng | Vai | Chuyển sang |
|---|---|---|---|
| `parsing/ingest.py` | 44 | `vectors = await embedder.embed(chunks)` | `embed_documents` |
| `tools/wiki.py` | 38 | `(vec,) = await embedder.embed([query])` | `embed_query` |
| `api/admin.py` | 92 | chỉ là **docstring** nhắc `_DeterministicDevEmbedder.embed()` | không đổi |

**Mẫu bám theo — `agent/providers/together_client.py` (spec 07 G0).** Hai tính chất phải sao chép, spec §7 gọi tên trực tiếp:
1. `TOGETHER_BASE_URL` là **hằng số module**, không nhận override. Lý do trong comment gốc: nhận override sẽ biến class thành "client trỏ đâu cũng được" và làm cái tên nói dối.
2. Resolve model 3 lớp `.strip() or DEFAULT`:
   ```python
   resolved_model = (
       (model or "").strip()
       or (settings.together_embed_model or "").strip()
       or DEFAULT_TOGETHER_EMBED_MODEL
   )
   ```
   `.strip()` chứ không chỉ kiểm falsy — `"  "` cũng là model id vô nghĩa và nó truthy.

**`OpenAIEmbedder.__init__`** đã nhận `base_url` / `api_key` / `model` ⇒ `TogetherEmbedder` **KHÔNG** subclass nó được như `TogetherClient` làm, vì còn phải **override cả hai method để gắn prefix**. Spec §6 nói đúng điều này: *"override cả hai method để gắn prefix"*.

**PRE-E01 ✅ đã verify bằng curl thật** (spec §5 dòng 40): `POST https://api.together.xyz/v1/embeddings` → HTTP 200, **dim thật = 1024**, đường SDK `AsyncOpenAI(base_url=...)` chạy OK.

---

## 4. Vì sao (b)+(c)+(e) là gate đắt nhất — bối cảnh, không phải scope

Ba assertion này tồn tại vì **đúng ba lỗi đã xảy ra thật**, không phải vì cẩn thận thừa:

- **(c) `TOGETHER_EMBED_MODEL` rỗng** — spec 07 G0 đã cháy đúng ca này: `TOGETHER_MODEL=` rỗng ⇒ falsy ⇒ trượt `or` ⇒ client trỏ Together nhưng xin `gpt-4o-mini` ⇒ 404. **90 test vẫn xanh** vì test dùng fake client. Lưu ý thêm: `_blank_env_means_unset` **không cứu** được ca này ở mọi kiểu field (ISSUE-018) — nên `.strip() or DEFAULT` trong adapter là lớp phòng thủ thật, không phải thừa.
- **(e) gate bất đối xứng** — đây là assertion **quan trọng nhất của cả phase**. e5 hoán đổi prefix không crash, không sai type, không đỏ test thông thường: nó chỉ làm chất lượng retrieval tệ đi âm thầm. Test phải bắt được cả 3 ca hỏng: hoán đổi, thiếu một bên, thiếu cả hai.
- **(g) key không lộ qua `repr()`** — rẻ, và là thứ chỉ phát hiện được lúc đã rò.

## 5. Ranh giới — đừng làm quá

- **KHÔNG** đụng `db/models.py`, `_EMBED_DIM`, migration, `default_embedder()` — toàn bộ là **E1**. `ALLOWED_FILES` của E0 không có chúng; chạm vào là scope drift, checkpoint sẽ REFUSE.
- **KHÔNG** đổi `Embedder.embed` thành abstract-only hoặc xoá nó — impl cũ dựa vào.
- **KHÔNG** tự hạ/nâng `RISK` — Wyatt gán, agent không bao giờ tự đổi tier.
- Bước 5 là **STOP+WAIT (ANCHOR)** — dừng thật, không tự chạy tiếp sang E1.

## 6. Thứ tự thao tác đóng phase

```bash
# 1. TDD: viết tests/test_together_embedder.py TRƯỚC, confirm ĐỎ
.venv/bin/python -m pytest tests/test_together_embedder.py -x -q     # phải FAIL

# 2. Implement bước 2–4, chạy lại GATE
.venv/bin/python -m pytest tests/test_together_embedder.py -x -q     # phải PASS

# 3. GATE_FULL
.venv/bin/python -m pytest tests/ -q -m 'not live' \
  && .venv/bin/mypy app agent retrieval parsing storage db bridge tools \
  && .venv/bin/ruff check . && .venv/bin/ruff format --check .

# 4. SMOKE — phase này CÓ mặt runtime (gọi e5 thật) ⇒ N/A không hợp lệ
bash .claude/tools/adp-smoke.sh new "$PWD" docs/smokes/08-E0.md E0
#    → gọi e5 thật, dán OBSERVED bằng output THẬT (không viết "OK")
#    → ghi 'SMOKE: PASS ref=docs/smokes/08-E0.md' vào ADP block   ← TRƯỚC stamp
bash .claude/tools/adp-smoke.sh stamp "$PWD" docs/smokes/08-E0.md

# 5. Review + checkpoint
bash .claude/tools/adp-review.sh stamp ...    # REVIEW: PASS ref=… bound diff_sha256
bash .claude/tools/adp-checkpoint.sh
```

⚠️ Ghi dòng `SMOKE:` **là** một thay đổi trong `git diff HEAD`. Stamp trước rồi ghi sau ⇒ hash lệch ⇒ REFUSE. Đã dính đúng bẫy này với `REVIEW:` ở spec 06 F1.

---

## 7. Chặn trước khi bắt đầu

| # | Việc | Ai | Trạng thái |
|---|---|---|---|
| 1 | Ký `RISK` cho E0 | Wyatt | ✅ **medium, ký 2026-07-19** |
| 2 | `TOGETHER_API_KEY` có sẵn trong môi trường chạy SMOKE | Wyatt/Tân | ⏳ cần xác nhận |

PRE-E01 ✅ đã đóng. Không có blocker kỹ thuật nào khác — E0 không chạm DB, không chạm `RISK_PATHS`, không chờ Tân.

**Còn lại đúng một thứ chặn: `TOGETHER_API_KEY`.** Nó không chặn *viết code* (bước 1–4 chạy được với fake client) — nó chặn **đóng phase**, vì E0 có mặt runtime nên `SMOKE: N/A` không hợp lệ và SMOKE artifact phải dán output gọi e5 THẬT.
