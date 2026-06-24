## Day 20 — Model Serving & Inference Optimization Lab.
## llama.cpp throughout. No Docker. Cross-platform via 00-setup/*.

VENV     := .venv
PY       := $(VENV)/bin/python
PIP      := $(VENV)/bin/pip
LOCUST   := $(VENV)/bin/locust

# Detect OS for setup target. macOS, Linux, anything-else (Windows users use the .ps1 directly).
OS := $(shell uname -s 2>/dev/null || echo Unknown)

.DEFAULT_GOAL := help

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	      /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\nWindows users: run 00-setup/windows-setup.ps1 then call individual scripts directly.\n\n"

# ─────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────

probe: ## Probe hardware — writes hardware.json (no install)
	@python3 00-setup/detect-hardware.py

setup: ## Install deps + build llama-cpp-python + download models (auto-detects OS)
ifeq ($(OS),Darwin)
	@bash 00-setup/macos-setup.sh
else ifeq ($(OS),Linux)
	@bash 00-setup/linux-setup.sh
else
	@echo "Unknown OS '$(OS)'. On Windows: pwsh -ExecutionPolicy Bypass -File 00-setup/windows-setup.ps1"
	@exit 1
endif

# ─────────────────────────────────────────────────────────────
# Track 01 — Quickstart
# ─────────────────────────────────────────────────────────────

bench: ## Track 01 — TTFT/TPOT/P95 baseline + Q4_K_M vs Q2_K
	@$(PY) 01-llama-cpp-quickstart/benchmark.py

# ─────────────────────────────────────────────────────────────
# Track 02 — llama-server
# ─────────────────────────────────────────────────────────────

serve: ## Track 02 — start llama-server on :8080 (foreground)
	@bash 02-llama-cpp-server/start-server.sh

serve-native: ## Track 02 (observability) — native llama-server WITH /metrics on :8080 (needs `make build-llama`)
	@bash 02-llama-cpp-server/start-server-native.sh

smoke: ## Track 02 — smoke-test the running server
	@$(PY) 02-llama-cpp-server/smoke-test.py

load-10: ## Track 02 — locust 10 users, 1 min
	GEVENT_LOOP=libuv $(LOCUST) -f 02-llama-cpp-server/load-test.py --headless -u 10 -r 1 -t 1m --host http://localhost:8080

load-50: ## Track 02 — locust 50 users, 1 min
	GEVENT_LOOP=libuv $(LOCUST) -f 02-llama-cpp-server/load-test.py --headless -u 50 -r 1 -t 1m --host http://localhost:8080

metrics: ## Track 02 (observability) — record /metrics 60s (needs the native server: make serve-native)
	@$(PY) 02-llama-cpp-server/record-metrics.py --duration 60

# ─────────────────────────────────────────────────────────────
# Track 03 — Integration
# ─────────────────────────────────────────────────────────────

pipeline: ## Track 03 — run RAG → llama-server pipeline (server must be on :8080)
	@$(PY) 03-milestone-integration/pipeline.py

# ─────────────────────────────────────────────────────────────
# Bonus — llama.cpp source build + sweeps
# ─────────────────────────────────────────────────────────────

build-llama: ## Bonus — clone + build llama.cpp from source for your hardware
	@bash -c 'set -e; \
	  command -v cmake >/dev/null || { echo "cmake not found - run: make setup (installs cmake), or: brew install cmake" >&2; exit 1; }; \
	  cd BONUS-llama-cpp-optimization && \
	  if [ ! -d llama.cpp ]; then git clone --depth 1 --branch b9771 https://github.com/ggml-org/llama.cpp; fi; \
	  cd llama.cpp && \
	  cmake -B build $(LLAMA_CMAKE_FLAGS) -DGGML_NATIVE=ON && \
	  cmake --build build -j --config Release'

sweep-thread: ## Bonus — sweep -t (thread count)
	@$(PY) BONUS-llama-cpp-optimization/benchmarks/thread-sweep.py

sweep-quant: ## Bonus — sweep GGUF quantizations (Q2_K → Q8_0)
	@$(PY) BONUS-llama-cpp-optimization/benchmarks/quant-sweep.py

sweep-ctx: ## Bonus — sweep context length (prefill cost curve)
	@$(PY) BONUS-llama-cpp-optimization/benchmarks/ctx-len-sweep.py

sweep-batch: ## Bonus — sweep --batch-size and --ubatch-size
	@$(PY) BONUS-llama-cpp-optimization/benchmarks/batch-size-sweep.py

sweep-gpu: ## Bonus — sweep -ngl (GPU offload, needs CUDA/Metal/Vulkan/ROCm)
	@$(PY) BONUS-llama-cpp-optimization/benchmarks/gpu-offload-sweep.py

mlx-compare: ## Bonus (Apple Silicon only) — MLX vs llama.cpp Metal
	@$(PY) BONUS-mlx-macos/compare-mlx-vs-llama-cpp.py

# ─────────────────────────────────────────────────────────────
# Bonus §5 — Serving regimes (embedding serving + semantic cache)
# ─────────────────────────────────────────────────────────────

serve-embed: ## Bonus §5 — embedding server (llama_cpp.server --embedding) on :8081
	@bash 02-llama-cpp-server/start-embedding-server.sh

embed-demo: ## Bonus §5 — embedding/reranker serving demo (run `make serve-embed` first; --offline works with no server)
	@$(PY) BONUS-llama-cpp-optimization/embedding-serving.py

semantic-cache: ## Bonus §5 — semantic cache demo (needs `make serve` + `make serve-embed`; --offline works with no server)
	@$(PY) BONUS-llama-cpp-optimization/semantic-cache-demo.py

# ─────────────────────────────────────────────────────────────
# Submission readiness
# ─────────────────────────────────────────────────────────────

verify: ## Check artifacts + REFLECTION.md edited + screenshots present (run before push)
	@$(PY) scripts/verify.py

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────

clean: ## Wipe generated artifacts (keeps models/, REFLECTION.md, screenshots/)
	rm -rf $(VENV) hardware.json
	rm -f benchmarks/01-quickstart-results.* benchmarks/02-server-metrics.* benchmarks/02-server-results.*
	rm -f benchmarks/bonus-*.md benchmarks/bonus-*.json benchmarks/bonus-*.png
	@echo "Clean done. models/, submission/, and benchmarks/results.md kept."

clean-all: clean ## Wipe everything including downloaded models + llama.cpp source build
	rm -rf models BONUS-llama-cpp-optimization/llama.cpp

.PHONY: help probe setup bench serve serve-native smoke load-10 load-50 metrics pipeline \
        build-llama sweep-thread sweep-quant sweep-ctx sweep-batch sweep-gpu mlx-compare \
        serve-embed embed-demo semantic-cache \
        verify clean clean-all
