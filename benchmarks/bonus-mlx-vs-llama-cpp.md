# Bonus — MLX vs llama.cpp Metal

Tier: `Llama-3.2-3B-Instruct`

| runtime | TTFT P50 (ms) | TTFT P95 (ms) | decode (tok/s) |
|---|--:|--:|--:|
| llama.cpp (Metal) | 66.3 | 67.5 | 57.7 |
| MLX-LM | 16.5 | 18.4 | 60.7 |

MLX TTFT numbers are approximations (mlx-lm doesn't expose first-token timing as readily as llama-cpp-python's stream API). Trust the decode tok/s for the head-to-head; trust both implementations' P95 only as rough indicators.
