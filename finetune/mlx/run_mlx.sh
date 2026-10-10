#!/usr/bin/env bash
# Mac（Apple Silicon）主流程：训练 → 融合 → GGUF Q4_K_M → sha256
set -euo pipefail
cd "$(dirname "$0")/.."
LLAMA_CPP=${LLAMA_CPP:-$HOME/llama.cpp}
python -m mlx_lm lora -c mlx/lora.yaml
python -m mlx_lm fuse --model Qwen/Qwen2.5-1.5B-Instruct --adapter-path runs/mlx_adapters --save-path runs/merged
bash scripts/to_gguf.sh runs/merged runs/trip-qwen2.5-1.5b-lora
