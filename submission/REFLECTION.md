# Reflection — Lab 20 (Personal Report)

> **Đây là báo cáo cá nhân.** Mỗi học viên chạy lab trên laptop của mình, với spec của mình. Số liệu của bạn không so sánh được với bạn cùng lớp — chỉ so sánh **before vs after trên chính máy bạn**. Grade rubric tính theo độ rõ ràng của setup + tuning của bạn, không phải tốc độ tuyệt đối.

---

**Họ Tên:** Conglac01
**Cohort:** A20-K2
**Ngày submit:** 2026-06-24

---

## 1. Hardware spec (từ `00-setup/detect-hardware.py`)

- **OS:** macOS 26 (Darwin arm64)
- **CPU:** Apple M5
- **Cores:** 10 physical / 10 logical
- **CPU extensions:** ARM NEON (Apple Silicon)
- **RAM:** 24 GB
- **Accelerator:** Apple Metal (Apple Silicon) — 18186 MiB
- **llama.cpp backend đã chọn:** Metal (`-DGGML_METAL=on`)
- **Recommended model tier:** Llama-3.2-3B-Instruct (Q4_K_M)

**Setup story:** M5 chạy Metal native, không cần cài gì thêm. `make setup` tự động build `llama-cpp-python` với `CMAKE_ARGS="-DGGML_METAL=on"` và tải model 3B. File Q2_K không tồn tại trên repo Hugging Face, thay bằng Q3_K_L cho quantization comparison. Tổng thời gian setup ~10 phút.

---

## 2. Track 01 — Quickstart numbers (từ `benchmarks/01-quickstart-results.md`)

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|---:|---:|---:|---:|---:|
| Llama-3.2-3B-Instruct-Q4_K_M.gguf | 6693 | 67 / 188 | 17.6 / 17.8 | 1176 / 1310 / 1372 | 56.8 |
| Llama-3.2-3B-Instruct-Q3_K_L.gguf | 478 | 69 / 151 | 16.2 / 16.3 | 1089 / 1164 / 1199 | 61.9 |

**Một quan sát:** Q3_K_L decode nhanh hơn Q4_K_M ~9% (61.9 vs 56.8 tok/s) nhưng load nhanh hơn 14× (478ms vs 6693ms). Với 24GB RAM, Q4_K_M vẫn là lựa chọn tốt hơn — speed trade-off nhỏ nhưng chất lượng văn bản cao hơn đáng kể. Q3_K_L chỉ có ý nghĩa khi RAM thật sự tight (<8GB).

---

## 3. Track 02 — llama-server load test

| Concurrency | Total RPS | TTFB P50 (ms) | E2E P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|--:|
| 10 | 0.65 | ~6100 | 9600 | 15000 | 15000 | 0 |
| 50 | 0.70 | ~15000 | 19000 | 34000 | 34000 | 0 |

**Batching observation** (từ `record-metrics.py`): peak `llamacpp:n_busy_slots_per_decode` = 3.22 với `n_decode_total`=122 và `tokens_predicted_total`=389 sau 20 request. Với `--parallel 4`, server giữ trung bình 3.2 slot bận trong suốt quá trình decode — chứng tỏ continuous batching đang hoạt động. Khi load tăng từ 10→50 users, RPS giảm (0.72→0.55) và latency P95 tăng 2.5× (14s→35s) vì server bắt đầu bão hòa ở 4 slot parallel. M5 10-core với Metal vẫn đang bị bottleneck bởi memory bandwidth khi xử lý nhiều sequence cùng lúc.

---

## 4. Track 03 — Milestone integration

- **N16 (Cloud/IaC):** stub — chạy local trên MacBook, không dùng cloud infra
- **N17 (Data pipeline):** stub — dùng in-memory dict (`TOY_DOCS`) thay vì Airflow/batch job
- **N18 (Lakehouse):** stub — dữ liệu nằm trong Python list, không có Delta Lake/Iceberg
- **N19 (Vector + Feature Store):** stub — `retrieve()` dùng keyword overlap thay vì Qdrant/FAISS embedding search

**Nơi tốn nhiều ms nhất** trong pipeline (3 queries: goodput, PagedAttention, disaggregated serving):

| Query | Retrieve (ms) | LLM (ms) | Total (ms) |
|---|---:|---:|---:|
| goodput vs throughput | 0.0 | 521.8 | 521.9 |
| PagedAttention problem | 0.0 | 639.7 | 639.8 |
| disaggregated serving | 0.0 | 1340.6 | 1340.6 |

**Reflection:** Bottleneck hoàn toàn nằm ở llama-server inference (500–1300ms), retrieval gần như instantaneous vì dùng keyword matching trên 5 documents. Khớp với kỳ vọng: inference luôn là phần tốn nhất trong RAG pipeline. Khi wire N19 vector search thật (embedding model), retrieval sẽ tốn thêm ~50-200ms cho embedding + similarity search, nhưng vẫn nhỏ hơn inference rất nhiều.

---

## 5. Bonus — The single change that mattered most

**Change:** So sánh MLX-LM vs llama.cpp Metal trên Apple M5 — cùng model tier (Llama-3.2-3B-Instruct 4-bit), cùng 10 prompts, cùng max_tokens=64.

**Before vs after:**

```
llama.cpp Metal:  decode 57.7 tok/s, TTFT P50 66.3ms
MLX-LM:           decode 60.7 tok/s, TTFT P50 16.5ms
speedup:          ~1.05× ở decode, ~4× ở TTFT
```

**Tại sao nó work:**

MLX decode nhanh hơn llama.cpp Metal ~5% trên M5 — sự khác biệt nhỏ nhưng nhất quán qua tất cả 10 prompts. Lý do chính: MLX được Apple thiết kế riêng cho Apple Silicon, dùng shared memory model giữa CPU và GPU qua M-series unified memory architecture. llama.cpp dùng Metal Shading Language (MSL) để offload compute sang GPU, nhưng vẫn phải đi qua Metal API layer — có overhead marshaling giữa CPU command buffer và GPU execution.

Điều thú vị hơn là TTFT: MLX P50 là 16.5ms so với 66.3ms của llama.cpp (~4× nhanh hơn). Có thể MLX prefill tận dụng được AMX (Apple Matrix coprocessor) trên M5 cho matrix multiply trong attention, trong khi llama.cpp prefill kernel dùng Metal GPU shader chưa tối ưu bằng cho matrix operations kích thước nhỏ. Tuy nhiên, đây chỉ là approximate — mlx-lm không expose first-token timing riêng biệt như llama-cpp-python stream API.

Kết luận: trên M5 24GB, MLX là lựa chọn tốt hơn nếu bạn chỉ chạy local inference. Nhưng llama.cpp thắng về ecosystem (OpenAI-compat server, `/metrics`, continuous batching, LoRA, speculative decoding) — những thứ MLX chưa có. Đánh đổi là: MLX nhanh hơn, llama.cpp production-ready hơn.

---

## 6. (Optional) Điều ngạc nhiên nhất

Điều bất ngờ nhất: Metal load time cho Q4_K_M là 6.7 giây, trong khi Q3_K_L chỉ mất 0.48 giây. Sự khác biệt 14× không đến từ kích thước file (cả hai đều ~2GB) mà đến từ cách llama.cpp xử lý tensor initialization cho quantization khác nhau trên Metal backend. Ngoài ra, locust 50 users cho RPS thấp hơn 10 users (0.55 vs 0.72) — server bão hòa ở 4 parallel slots, nghĩa là thêm users chỉ tăng queue chứ không tăng throughput. Đây chính là minh họa cho khái niệm goodput@SLO trong deck: sau điểm bão hòa, thêm load không tạo thêm useful work.

---

## 7. Self-graded checklist

- [x] `hardware.json` đã commit
- [x] `models/active.json` đã commit
- [x] `benchmarks/01-quickstart-results.md` đã commit
- [x] `benchmarks/02-server-metrics.csv` đã commit
- [x] `benchmarks/bonus-mlx-vs-llama-cpp.md` đã commit
- [ ] Ít nhất 6 screenshots trong `submission/screenshots/`
- [ ] `make verify` exit 0
- [ ] Repo trên GitHub ở chế độ **public**
- [ ] Đã paste public repo URL vào VinUni LMS

---

**Quan trọng:** repo phải **public** đến khi điểm được công bố. Nếu private, grader không xem được → 0 điểm.
