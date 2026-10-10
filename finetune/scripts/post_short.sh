#!/usr/bin/env bash
# 等短训练结束 → 合并 → GGUF Q4_K_M → 60 条评测 → 清理。日志 runs/post_short.log
cd "$(dirname "$0")/.." || exit 1
LOG=runs/post_short.log; rm -f runs/POST_SHORT_DONE runs/POST_SHORT_FAILED
exec >>"$LOG" 2>&1
fail() { echo "FAILED: $1"; echo "$1" > runs/POST_SHORT_FAILED; rm -rf runs/short_merged; exit 1; }
echo "[$(date)] waiting for 1023616"
while kill -0 1023616 2>/dev/null; do sleep 60; done
[ -f runs/short_lora/adapter_config.json ] || fail "training ended without adapter (see runs/short_train.log)"
source /workspace/venv/bin/activate
echo "[$(date)] merge"; python peft/merge_peft.py --base /workspace/hf/Qwen2.5-1.5B-Instruct --lora runs/short_lora --out runs/short_merged || fail merge
echo "[$(date)] gguf"; LLAMA_CPP=/workspace/llama.cpp bash scripts/to_gguf.sh runs/short_merged runs/short || fail gguf
rm -rf runs/short_merged
echo "[$(date)] eval"; mkdir -p results
(cd results && python ../scripts/eval_appfmt.py ../runs/short-Q4_K_M.gguf --tag short --limit 60) || fail eval
echo "[$(date)] done"; touch runs/POST_SHORT_DONE
