# 08-Task-OhanaAISeller-EmbedderSwap-E5

<!-- spec-generator v2.3 · Branch B (Wyatt directive 2026-07-19 "Tạo spec ISSUE-016") -->
<!-- PROJECT: Ohana AI Seller. NOT ONFA wallet. §4 dùng safety→trust→stability→growth, KHÔNG dùng Survival Framework LR/WP/TV/UR. -->
<!-- ADP:MANIFEST inherited từ ohana-ai/CLAUDE.md §5:
GATE_RUNNER: .venv/bin/python -m pytest -q -x
RISK_PATHS: agent/orchestrator.py, agent/policy_gate.py, tools/registry.py, bridge/, auth/, db/migrations, api/webhook.py, api/inbox.py, api/admin.py, api/chat.py
SPEC_DIR: docs/tasks
EXECUTOR_SKILL: drnick-coder
CHECKPOINT_PREFIX: adp
-->

## §0 — Header

| Field | Value |
|---|---|
| Title | Embedder swap OpenAI-1536 → Together e5-1024 (đóng ISSUE-016) |
| Parent | ADR PRE-007 (ACCEPTED 2026-07-19) — Consequences §"F1 / ISSUE-016 làm lại" |
| Depends-on | Spec 05 (config + embedder wiring, DONE) · Spec 07 G0 (`TogetherClient` + `DEFAULT_TOGETHER_MODEL`, DONE) |
| Unblocks | ISSUE-016 (high, OPEN từ 2026-07-16) · F1 wiki-RAG dùng được cho khách thật |
| Owner | R: Tân (dev lead) · A: Wyatt (RISK finalize) |
| Branch | `main` (commit thẳng — khớp thực tế spec 06/07) |
| Duration | 1–2 ngày |
| Spec type | Full · Workflow mode: IMPLEMENT |

---

## §1 — Problem Statement

**ISSUE-016 đã đổi bản chất hai lần và giờ là công việc thật, không phải chờ ai duyệt.**

- **Gốc (2026-07-16):** F1 wiki-RAG tick DONE nhưng chưa từng chạy với embedding thật — gate dùng `FakeEmbedder` inline.
- **Lần 1 (spec 05):** `app/config.py` land, `OpenAIEmbedder` hết `ModuleNotFoundError`, `default_embedder()` env-selecting. Nhưng live acceptance vẫn chưa chạy ⇒ vẫn OPEN.
- **Lần 2 (ADR PRE-007, ACCEPTED 2026-07-19):** provider chốt **Together open-weight**, embedding chuyển sang **`intfloat/multilingual-e5-large-instruct` (1024-dim)**. Nghĩa là live acceptance phải chạy trên **e5, KHÔNG phải OpenAI** — mọi kết quả cũ trên OpenAI không áp dụng.

Sau khi ADR ký, blocker không còn là "chờ chữ ký" mà là **4 việc chưa spec nào nhận**. Spec này nhận cả 4.

**Audit on-disk 2026-07-19 — verify bằng GỌI THẬT, không giả định** *(bài học spec 07: danh sách `/v1/models` không phải bằng chứng)*:

1. ✅ **e5 phục vụ được trên Together.** `POST /v1/embeddings` → HTTP 200. **Dimension THẬT = 1024** (khớp ADR). SDK `AsyncOpenAI(base_url="https://api.together.xyz/v1").embeddings.create(...)` chạy OK ⇒ `TogetherEmbedder` tái dùng được đường SDK y như `TogetherClient`.
2. ✅ **Tiếng Việt phân tách đúng.** `cos(query, passage-đúng-chủ-đề) = 0.9188` vs `cos(query, passage-sai-chủ-đề) = 0.7939`.
3. ✅ **Chunker KHÔNG cần đổi.** `parsing/chunk.py max_chars=800` là **ký tự**; đo thật tiếng Việt ≈ **4.1 ký tự/token** ⇒ 800 ký tự ≈ **195 token**, trần e5 = **514 token** ⇒ dư **2.6×**. (Rủi ro truncate âm thầm bị loại khỏi spec này bằng phép đo, không bằng phỏng đoán.)
4. ⚠️ **`Embedder` ABC KHÔNG phân biệt query vs passage — đây là lỗ hổng thiết kế chưa ai nêu.** `tools/wiki.py:38` embed **query**; `parsing/ingest.py:44` embed **passage**; cả hai gọi CÙNG một `embed()`. e5 yêu cầu prefix khác nhau (`query: ` / `passage: `). Không sửa ABC thì không có chỗ nào đặt prefix cho đúng.
5. 📊 **Prefix có tác dụng, nhưng KHÔNG phải thảm hoạ như ADR ngụ ý.** Đo: biên phân tách **+0.1249** (có prefix) vs **+0.1101** (không) — tốt hơn ~13% **trên một cặp mẫu**. ADR viết "thiếu thì retrieval tụt âm thầm" — đúng hướng, nhưng tôi KHÔNG đo được mức thảm hoạ, và một mẫu không đủ kết luận. Rủi ro thật nằm ở chỗ khác: **BẤT ĐỐI XỨNG** (corpus embed có prefix, query embed không — hoặc ngược lại) tệ hơn hẳn việc bỏ cả hai. Đó mới là thứ phải gate.
6. ✅ **Re-embed hiện tại là trivial.** Bảng `embeddings` có đúng **2 row** (`_platform` 1, `shop_a` 1 — test fixture). Corpus thật chưa land (PRE-003). ⇒ Làm swap **BÂY GIỜ** rẻ hơn nhiều so với sau khi có corpus.

---

## §2 — Goal

**VI:** F1 wiki-RAG chạy trên embedding THẬT của Together (e5, 1024-dim), có bằng chứng live — đóng ISSUE-016. Cột vector đổi 1536→1024 an toàn, prefix `query:`/`passage:` đặt đúng chỗ và được test canh bất đối xứng.

**EN:** F1 wiki-RAG runs on Together's real e5 embeddings (1024-dim) with live evidence, closing ISSUE-016. The vector column migrates 1536→1024 safely, and the `query:`/`passage:` prefixes are applied at the right layer with a test guarding against the asymmetric-prefix failure.

---

## §3 — Scope

### Sub-task A — `TogetherEmbedder` + query/passage split (Phase E0)
- `agent/embedder.py`: `Embedder` ABC += `embed_query(text)` / `embed_documents(texts)` với **default impl delegate về `embed()`** ⇒ `OpenAIEmbedder` + `_DeterministicDevEmbedder` KHÔNG vỡ.
- `agent/providers/together_embedder.py`: `TogetherEmbedder(Embedder)` — base_url Together, model + key từ `Settings`, **override cả hai method để gắn prefix**.
- `app/config.py` += `together_embed_model` (default `intfloat/multilingual-e5-large-instruct`) + `DEFAULT_TOGETHER_EMBED_MODEL` + `EMBED_DIM` hằng số dùng chung.
- Files: `agent/embedder.py`, `agent/providers/together_embedder.py`, `app/config.py`, `tests/test_together_embedder.py`.

### Sub-task B — Migration 1536→1024 + wire factory (Phase E1)
- `db/models.py`: `_EMBED_DIM` 1536 → 1024 (đọc từ `app/config.EMBED_DIM`, một nguồn sự thật).
- `db/migrations/versions/0004_embedding_dim_1024.py` — **destructive có chủ ý** (xem §8).
- `api/admin.py default_embedder()`: chọn Together khi có `together_api_key`; giữ nguyên tính chất **KHÔNG raise ở factory** (nó chạy lúc import trong `app/main.py`).
- Files: `db/models.py`, `db/migrations/versions/0004_*.py`, `api/admin.py`, `tests/test_embedder_wiring.py`, `tests/test_config.py`.

### Sub-task C — Live acceptance trên e5 (Phase E2)
- `tests/test_wiki_rag_live.py` chạy trên **e5**, không phải OpenAI.
- Đóng ISSUE-016 trong `docs/memory/KNOWN_ISSUES.md` + gỡ cảnh báo F1 trong `CLAUDE.md`.
- Files: `tests/test_wiki_rag_live.py`, `docs/memory/KNOWN_ISSUES.md`, `CLAUDE.md`.

### Out of scope (cố ý)
- ❌ **Đổi `parsing/chunk.py`** — đo được là dư 2.6× trần token, không có lý do chạm.
- ❌ **Re-embed corpus thật** — corpus chưa tồn tại (PRE-003). Migration để lại đường chạy lại; nội dung là việc của spec PRE-003.
- ❌ **Bỏ `OpenAIEmbedder`** — giữ làm adapter thay thế; xoá là việc riêng nếu Wyatt muốn.
- ❌ **Tuning retrieval / top-k / reranker** — đổi chất lượng là trục khác, không trộn vào swap.

---

## §4 — Safety Gate Check (trục Ohana)

Priority order: **safety → user trust → stability → growth**. *(Ohana KHÔNG dùng Survival Framework fintech — xem CLAUDE.md §1.)*

| Trục | Đánh giá | Verdict |
|---|---|---|
| **Safety** | Rủi ro #1 = **hỏng âm thầm ở tầng retrieval**. Vector sai dim thì Postgres từ chối (ồn ào, an toàn). Nhưng **prefix bất đối xứng** thì KHÔNG có lỗi nào: ingest và query vẫn chạy, chỉ là chunk trả về kém liên quan hơn → AI trả lời khách bằng căn cứ sai. Không stack trace, không alert. Mitigation: gate bất đối xứng ở E0 + live acceptance E2. | ⚠️ FLAG — gate bất đối xứng là điều kiện DONE của E0 |
| **User trust** | Đây là bước biến F1 từ "code-complete" thành "đã chứng minh". e5 multilingual xử tiếng Việt tốt hơn embedding English-centric ⇒ nâng chất lượng, không chỉ compliance. | PASS |
| **Stability** | Migration destructive nhưng hiện chỉ 2 row test fixture — **rẻ nhất trong toàn bộ vòng đời dự án để làm bây giờ**. Càng để lâu càng đắt. Không đụng `agent/orchestrator.py` / `policy_gate.py` / đường gửi khách. | PASS |
| **Growth** | Gỡ blocker high đã OPEN 3 ngày, mở đường cho PRE-003 ingest corpus thật. | PASS |

**RED FLAG scan:**
- [x] Vector dim mismatch → Postgres từ chối ở tầng DB, **không** lọt âm thầm. Test E1 chứng minh.
- [x] Prefix bất đối xứng → **KHÔNG** có lỗi runtime ⇒ phải gate bằng test (E0), không bằng review mắt.
- [x] Mất dữ liệu do migration → có chủ ý, ghi rõ §8, và **hiện chỉ 2 row test**. Down-migration cũng mất dữ liệu — ghi rõ, không giả vờ reversible.
- [x] `shop_id` scope → không đụng `retrieval/pgvector.py` shop-scope; test tenant-isolation hiện có phải vẫn xanh.
- [x] Key rò → `TOGETHER_API_KEY` chỉ qua `Settings`, không log, không vào response.
- [x] `default_embedder()` raise lúc import → **cấm** (spec 05 P1 đã học; nó chạy lúc import `app/main.py`, raise = cả app không boot).

---

## §5 — Source Files & Context (đọc TRƯỚC khi sửa)

| File | Vì sao |
|---|---|
| `agent/embedder.py` | ABC hiện chỉ có `embed()` — chỗ phải mở rộng |
| `agent/providers/openai_embedder.py` | Adapter mẫu; `TogetherEmbedder` bám shape này |
| `agent/providers/together_client.py` | **Mẫu gần nhất** — spec 07 G0 đã giải đúng bài "trỏ Together, model/key từ Settings, không rơi về default provider khác" |
| `app/config.py` | `DEFAULT_TOGETHER_MODEL`, `_blank_env_means_unset` (env rỗng ⇒ coi như chưa set) |
| `db/models.py:35,77` | `_EMBED_DIM` + `Vector(_EMBED_DIM)` |
| `db/migrations/versions/0003_foundation_entities.py` | Mẫu migration reversible gần nhất |
| `api/admin.py:73-110` | `default_embedder()` + lý do KHÔNG raise ở factory |
| `parsing/ingest.py:44` · `tools/wiki.py:38` | Hai call-site: passage vs query |
| `retrieval/pgvector.py` | Shop-scope SQL-level — KHÔNG được đụng |
| `docs/adr/2026-07-18-hosting-region.md` | Consequences: 4 việc spec này nhận |
| `docs/memory/KNOWN_ISSUES.md` ISSUE-016 | Định nghĩa "đóng" |

---

## §6 — Pre-flight Checks

```
PRE-E01: Together phục vụ e5, dimension = 1024.
  Command: curl -s -X POST https://api.together.xyz/v1/embeddings \
             -H "Authorization: Bearer $TOGETHER_API_KEY" \
             -d '{"model":"intfloat/multilingual-e5-large-instruct","input":["passage: test"]}' \
           | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"][0]["embedding"]))'
  Expected: 1024
  Status: ✅ ĐÃ VERIFY 2026-07-19 (HTTP 200, dim=1024)
  If fail: STOP — ADR dựa trên giả định sai, báo Wyatt trước khi viết code.

PRE-E02: Postgres sống + pgvector, và biết chính xác có bao nhiêu row sẽ MẤT.
  Command: psql "$DATABASE_URL" -c "select count(*) from embeddings;"
  Expected: một con số. Nếu > 100 ⇒ STOP, migration cần chiến lược re-embed thật
            (spec này giả định corpus chưa land).
  Status: ✅ ĐÃ VERIFY 2026-07-19 — 2 row (_platform 1, shop_a 1), đều là test fixture.

PRE-E03: Số migration chưa bị ai lấy — kiểm CẢ trên đĩa LẪN trong spec khác.
  Command: ls db/migrations/versions/
           grep -rhoE '0[0-9]{3}' docs/tasks/*.md | sort -u    # ← bước này ban đầu tôi BỎ SÓT
  Expected: số chọn không xuất hiện ở cả hai nơi.
  Status: ⚠️ **VA CHẠM ĐÃ PHÁT HIỆN 2026-07-19.** Bản đầu của check này chỉ đối chiếu file
          TRÊN ĐĨA (0001/0002/0003) rồi kết luận "0004 trống" — sai phạm vi. Spec 03 §8
          (dòng 164) đã đặt gạch `Phase 1 (0004), Phase 2 (0005), Phase 5 (0006)` từ trước.

  **Luật chốt (áp cho mọi spec sau):** số migration cấp theo **THỨ TỰ LAND**, không theo thứ
  tự lập kế hoạch. Alembic nối chuỗi bằng `down_revision`, không bằng số trong tên file — nên
  số trong spec chưa chạy chỉ là **dự kiến**, không phải chỗ đã giữ.

  Áp vào đây: spec 03 đang **BLOCKED** (chờ Tân, 0/10), spec 08 chạy được ngay ⇒ **spec 08 lấy
  0004**, spec 03 dịch xuống 0005/0006/0007 khi nó thực sự chạy. Đã ghi cảnh báo vào spec 03 §8.
  Người execute spec 03 PHẢI chạy lại check này, KHÔNG tin số ghi sẵn trong spec.

PRE-E04: Wyatt chốt số phận vector cũ.
  Câu hỏi: 2 row hiện có là test fixture — XOÁ khi migrate (đơn giản, đúng bản chất)
           hay phải giữ (cần chiến lược re-embed)?
  Status: ⏳ CHỜ WYATT — xem §14.
  If "giữ": E1 phải thêm bước re-embed, spec này phải sửa trước khi chạy.
```

---

## §7 — Execute Steps

### Phase E0 — `TogetherEmbedder` + query/passage split
<!-- ADP:PHASE E0 -->
STATUS: TODO
ROADMAP: GD0-EMBED
GOAL: `TogetherEmbedder` gọi được e5 thật (1024-dim), prefix `query:`/`passage:` đặt ĐÚNG bên; `Embedder` ABC có `embed_query`/`embed_documents` với default delegate ⇒ `OpenAIEmbedder` + `_DeterministicDevEmbedder` KHÔNG vỡ; gate BẤT ĐỐI XỨNG đỏ khi prefix lệch bên.
APPROACH: ABC thêm 2 concrete method (KHÔNG abstract — thêm abstract sẽ phá mọi impl hiện có). `TogetherEmbedder` bám shape `together_client.py` spec 07 G0: base_url hằng số, model/key từ `Settings`, resolve model bằng `.strip() or DEFAULT` để chuỗi rỗng không trượt sang provider khác (đúng bug 2026-07-19). Call-site (`ingest.py`/`wiki.py`) chuyển sang `embed_documents`/`embed_query` — prefix là việc của ADAPTER, không phải của call-site, vì OpenAI không dùng prefix.
ALLOWED_FILES: agent/embedder.py, agent/providers/together_embedder.py, app/config.py, parsing/ingest.py, tools/wiki.py, tests/test_together_embedder.py, docs/reviews/, docs/smokes/, docs/tasks/08-Task-OhanaAISeller-EmbedderSwap-E5.md
GATE: .venv/bin/python -m pytest tests/test_together_embedder.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: medium (SIGNED Wyatt 2026-07-19 — chốt theo đề xuất. Nâng trên floor `low` vì adapter provider mới + đổi ABC dùng chung; tiền lệ spec 07 G0.)
BLOCKED_BY: PRE-E01 ✅
SMOKE: (điền khi chạy — có mặt runtime: gọi e5 thật)
<!-- /ADP -->

1. `tests/test_together_embedder.py` (RED): (a) `TogetherEmbedder` là `Embedder`; (b) trỏ base_url Together, model/key từ `Settings`, KHÔNG hardcode; (c) `TOGETHER_EMBED_MODEL` rỗng ⇒ rơi về default, KHÔNG rơi sang model provider khác; (d) `embed_query` gắn `query: `, `embed_documents` gắn `passage: ` — kiểm bằng fake client bắt được text GỬI ĐI; (e) **gate bất đối xứng**: prefix không được hoán đổi/thiếu một bên; (f) `OpenAIEmbedder` + `_DeterministicDevEmbedder` vẫn thoả ABC sau khi thêm method (không vỡ impl cũ); (g) key KHÔNG lộ qua `repr()`.
2. `agent/embedder.py`: thêm 2 concrete method + docstring nói rõ vì sao default là delegate.
3. `agent/providers/together_embedder.py` + `app/config.py` 2 field.
4. `parsing/ingest.py` → `embed_documents`; `tools/wiki.py` → `embed_query`.
5. **STOP+WAIT** (ANCHOR).

### Phase E1 — Migration 1536→1024 + wire factory
<!-- ADP:PHASE E1 -->
STATUS: TODO
ROADMAP: GD0-EMBED
GOAL: Cột `embeddings.embedding` là `Vector(1024)`; `_EMBED_DIM` một nguồn sự thật; `default_embedder()` trả `TogetherEmbedder` khi có `together_api_key`, KHÔNG raise ở factory; vector sai dim bị Postgres TỪ CHỐI (chứng minh bằng test, không bằng lời).
APPROACH: Migration **destructive có chủ ý** — 1536→1024 KHÔNG phải phép chiếu, vector cũ vô nghĩa ở không gian mới. `DELETE FROM embeddings` rồi `ALTER TYPE`, ghi rõ trong docstring migration + §8. Down-migration cũng xoá — reversible về SCHEMA, KHÔNG reversible về DỮ LIỆU; nói thẳng thay vì giả vờ. `default_embedder()` ưu tiên Together, fallback OpenAI, cuối cùng dev-embedder; giữ nguyên tính chất không-raise-ở-factory (spec 05 P1).
ALLOWED_FILES: db/models.py, db/migrations/versions/, api/admin.py, app/config.py, tests/test_embedder_wiring.py, tests/test_config.py, tests/test_embedding_dim.py, docs/reviews/, docs/smokes/, docs/tasks/08-Task-OhanaAISeller-EmbedderSwap-E5.md
GATE: .venv/bin/python -m pytest tests/test_embedding_dim.py tests/test_embedder_wiring.py -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/mypy app agent retrieval parsing storage db bridge tools && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: high (SIGNED Wyatt 2026-07-19 — chốt theo đề xuất. Nâng trên floor `medium` vì migration ĐỔI schema và XOÁ dữ liệu, không chỉ chạm file. ⇒ per-step confirm + human review artifact `human=<file>` ký `REVIEWED_BY` bound cùng diff; auto-verdict Haiku KHÔNG đủ.)
BLOCKED_BY: E0, PRE-E02 ✅, PRE-E03 ✅, PRE-E04 ⏳
SMOKE: (điền khi chạy — có mặt runtime: migration trên Postgres thật)
<!-- /ADP -->

6. `tests/test_embedding_dim.py` (RED): (a) cột là `Vector(1024)` sau migrate; (b) **chèn vector 1536 ⇒ Postgres RAISE** (chứng minh dim mismatch không lọt âm thầm); (c) migration up→down→up sạch; (d) `_EMBED_DIM` khớp `EMBED_DIM` của config (không hai nguồn sự thật).
7. Cập nhật `db/models.py` + viết `0004_embedding_dim_1024.py`.
8. `default_embedder()` chọn Together + cập nhật test hardcode 1536 (`test_config.py`, `test_embedder_wiring.py`) — **cập nhật cho khớp thực tế mới, KHÔNG xoá test**.
9. Chạy migration trên Postgres thật, verify bằng `\d+ embeddings`.
10. **STOP+WAIT** (ANCHOR — nếu Wyatt chốt high thì confirm mỗi bước).

### Phase E2 — Live acceptance trên e5 (đóng ISSUE-016)
<!-- ADP:PHASE E2 -->
STATUS: TODO
ROADMAP: GD0-EMBED
GOAL: `tests/test_wiki_rag_live.py -m live` PASS **trên e5 thật** — ingest doc mẫu → search trả đúng chunk, có bằng chứng dán vào SMOKE artifact. ISSUE-016 chuyển RESOLVED, cảnh báo F1 trong CLAUDE.md gỡ.
APPROACH: Sửa live test trỏ e5 (không phải OpenAI). Test phải kiểm **thứ hạng**, không chỉ "có trả về gì đó": chunk đúng chủ đề phải xếp TRÊN chunk sai chủ đề — đó mới là điều F1 hứa. Skip sạch khi thiếu key (không FAIL giả).
ALLOWED_FILES: tests/test_wiki_rag_live.py, docs/memory/KNOWN_ISSUES.md, CLAUDE.md, docs/reviews/, docs/smokes/, docs/tasks/08-Task-OhanaAISeller-EmbedderSwap-E5.md
GATE: .venv/bin/python -m pytest tests/test_wiki_rag_live.py -m live -x -q
GATE_FULL: .venv/bin/python -m pytest tests/ -q -m 'not live' && .venv/bin/ruff check . && .venv/bin/ruff format --check .
RETRY: 0/3
RISK: low (SIGNED Wyatt 2026-07-19 — chốt theo đề xuất. ALLOWED_FILES KHÔNG giao RISK_PATHS; chỉ test + docs.)
BLOCKED_BY: E1
SMOKE: (điền khi chạy — chính phase này LÀ smoke; artifact phải dán output live test thật)
<!-- /ADP -->

11. Sửa `test_wiki_rag_live.py` sang e5 + assert **thứ hạng** chunk.
12. Chạy `-m live` với key thật, dán output vào SMOKE artifact.
13. Đóng ISSUE-016 + gỡ cảnh báo F1 trong `CLAUDE.md`.
14. **STOP+WAIT**.

---

## §8 — DB Changes

**Migration `0004_embedding_dim_1024.py` — DESTRUCTIVE CÓ CHỦ Ý.**

```sql
-- up
DELETE FROM embeddings;                                   -- xem ghi chú dưới
ALTER TABLE embeddings ALTER COLUMN embedding TYPE vector(1024);

-- down
DELETE FROM embeddings;
ALTER TABLE embeddings ALTER COLUMN embedding TYPE vector(1536);
```

**Vì sao XOÁ chứ không chuyển đổi.** Vector 1536-dim của OpenAI và 1024-dim của e5 nằm ở **hai không gian ngữ nghĩa khác nhau**. Không có phép chiếu nào biến cái này thành cái kia — cắt bớt 512 chiều cho ra vector vô nghĩa mà `pgvector` vẫn nhận và vẫn trả kết quả *trông như* hợp lệ. Đó là hỏng âm thầm ở dạng tệ nhất. Xoá là lựa chọn duy nhất trung thực; dữ liệu đúng phải tới từ re-embed.

**Reversible về SCHEMA, KHÔNG reversible về DỮ LIỆU.** `down` khôi phục kiểu cột nhưng **không** khôi phục vector. Nói thẳng ở đây thay vì để ai đó phát hiện lúc rollback lúc 2 giờ sáng.

**Chi phí hiện tại: 2 row test fixture.** Đây là **thời điểm rẻ nhất trong vòng đời dự án** để làm việc này. Sau khi PRE-003 land corpus thật, cùng migration này sẽ cần cửa sổ re-embed + kế hoạch downtime.

⚠️ **Điều kiện an toàn:** nếu lúc chạy `select count(*) from embeddings` > 100 ⇒ **STOP**. Spec này được viết cho trạng thái corpus-chưa-land; đừng chạy mù.

---

## §9 — i18n

Không áp dụng — spec này không chạm UI. *(Mục giữ lại để khớp template 14 mục.)*

---

## §10 — Post-checks

```
ruff check . && ruff format --check .
mypy app agent retrieval parsing storage db bridge tools
pytest -q -m 'not live'                    (toàn bộ — 109 test hiện tại phải KHÔNG giảm)

Migration thật:
  alembic upgrade head && psql "$DATABASE_URL" -c "\d+ embeddings" | grep vector
  Expected: vector(1024)
  alembic downgrade -1 && alembic upgrade head        (up→down→up sạch)

Live (E2, bắt buộc để đóng ISSUE-016):
  TOGETHER_API_KEY=... pytest tests/test_wiki_rag_live.py -m live -x -q
  Expected: PASS, và chunk đúng chủ đề xếp TRÊN chunk sai chủ đề

Bất đối xứng prefix (E0):
  pytest tests/test_together_embedder.py -k asymmetr -x -q
  Expected: PASS. Hoán đổi prefix giữa query/passage ⇒ ĐỎ.

Tenant isolation KHÔNG được vỡ:
  pytest tests/test_tenant_isolation.py -x -q
```

---

## §11 — Deliverables

| File | Trạng thái |
|---|---|
| `agent/providers/together_embedder.py` | NEW |
| `db/migrations/versions/0004_embedding_dim_1024.py` | NEW |
| `tests/test_together_embedder.py` · `tests/test_embedding_dim.py` | NEW |
| `agent/embedder.py` · `app/config.py` · `db/models.py` · `api/admin.py` | MODIFIED |
| `parsing/ingest.py` · `tools/wiki.py` | MODIFIED (đổi sang embed_documents / embed_query) |
| `tests/test_config.py` · `tests/test_embedder_wiring.py` · `tests/test_wiki_rag_live.py` | MODIFIED |
| `docs/memory/KNOWN_ISSUES.md` · `CLAUDE.md` | MODIFIED (đóng ISSUE-016) |

Commit: `adp/08-Task-OhanaAISeller-EmbedderSwap-E5 phase-<id>: <concern>`

---

## §12 — Constraints

🚫 **KHÔNG** để `default_embedder()` raise ở factory — nó chạy lúc import `app/main.py`, raise = cả app không boot (spec 05 P1 đã học).
🚫 **KHÔNG** đặt prefix ở call-site (`ingest.py`/`wiki.py`) — OpenAI không dùng prefix; đặt ở call-site là ép ngữ nghĩa của một provider lên mọi provider. Prefix thuộc về ADAPTER.
🚫 **KHÔNG** thêm abstract method vào `Embedder` — phá mọi impl hiện có. Concrete + default delegate.
🚫 **KHÔNG** xoá test hardcode 1536 — **cập nhật** chúng. Xoá test là xoá cảnh báo.
🚫 **KHÔNG** đụng `retrieval/pgvector.py` shop-scope hay `parsing/chunk.py` (đo được là dư 2.6× trần token).
🚫 **KHÔNG** chạy migration khi `count(*) > 100` mà chưa có kế hoạch re-embed.
🚫 **KHÔNG** tick DONE ngoài `adp-checkpoint.sh`. Mỗi phase phải có `SMOKE:` (PASS ref= hoặc N/A + lý do) — gate mới 2026-07-19.
🚫 **KHÔNG** tin danh sách model thay cho một cuộc gọi thật (bài học spec 07: `/v1/models` liệt kê cả model không phục vụ được, kèm bảng giá).

---

## §13 — Tracking

| Phase | Concern | RISK (SIGNED) | STATUS | BLOCKED_BY | EVIDENCE |
|---|---|---|---|---|---|
| E0 | `TogetherEmbedder` + query/passage split | medium | TODO | — | — |
| E1 | Migration 1536→1024 + wire factory | **high** | TODO | E0, PRE-E04 | — |
| E2 | Live acceptance e5 → đóng ISSUE-016 | low | TODO | E1 | — |

> RISK = **đề xuất**. Wyatt chốt lúc duyệt spec. EVIDENCE do `adp-checkpoint.sh` ghi, SMOKE do `adp-smoke.sh` stamp.

---

## §14 — Wyatt chốt trước khi execute

- [ ] **PRE-E04 — số phận 2 vector cũ:** xoá khi migrate (đề xuất — chúng là test fixture, và vector 1536 không chuyển được sang không gian 1024) hay phải giữ?
- [ ] **RISK tier:** E0 `medium`? · **E1 `high`?** (migration destructive — nếu high thì cần human review artifact bound cùng diff, không đủ auto-verdict) · E2 `low`?
- [ ] **Giữ hay bỏ `OpenAIEmbedder`** sau khi Together thành mặc định? (Đề xuất: GIỮ làm adapter thay thế — chi phí bằng 0, và nó là bằng chứng rằng lớp abstraction hoạt động thật.)
- [ ] **Định nghĩa "đóng ISSUE-016"**: live test PASS trên e5 là đủ, hay cần thêm điều kiện gì?
