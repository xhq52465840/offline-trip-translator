#!/usr/bin/env bash
# r4 盒子 CPU 混合 LoRA（out_mix，约 45% 回放含 FLORES dev）：训练 → 合并 → GGUF → App 60 条 + 公开集评测。
# 【盒子 CPU 结果】非 Mac MLX、非真机。日志 runs/mix_r4.log，完成标志 runs/MIX_R4_DONE / MIX_R4_FAILED
cd "$(dirname "$0")/.." || exit 1
STEPS=${STEPS:-100}; LOG=runs/mix_r4.log; rm -f runs/MIX_R4_DONE runs/MIX_R4_FAILED
exec >>"$LOG" 2>&1
fail() { echo "FAILED: $1"; echo "$1" > runs/MIX_R4_FAILED; rm -rf runs/mix_r4_merged; exit 1; }
source /workspace/venv/bin/activate
echo "[$(date)] train steps=$STEPS"
python peft/train_peft.py --model /workspace/hf/Qwen2.5-1.5B-Instruct --data out_mix --out runs/mix_r4_lora \
  --steps "$STEPS" --bs 2 --grad_accum 4 --max_len 512 --eval_every 50 --threads 8 || fail train
[ -f runs/mix_r4_lora/adapter_config.json ] || fail "no adapter"
echo "[$(date)] merge"; python peft/merge_peft.py --base /workspace/hf/Qwen2.5-1.5B-Instruct --lora runs/mix_r4_lora --out runs/mix_r4_merged || fail merge
echo "[$(date)] gguf"; LLAMA_CPP=/workspace/llama.cpp bash scripts/to_gguf.sh runs/mix_r4_merged runs/mix_r4 || fail gguf
rm -rf runs/mix_r4_merged
cd results || exit 1
echo "[$(date)] eval app"; python ../scripts/eval_appfmt.py ../runs/mix_r4-Q4_K_M.gguf --tag box_mix_r4 --limit 60 || fail eval_app
echo "[$(date)] eval public"; python ../scripts/eval_public.py ../runs/mix_r4-Q4_K_M.gguf --tag box_mix_r4 --threads 8 > ../runs/public_box_mix_r4.log 2>&1 || fail eval_public
echo "[$(date)] done"; touch ../runs/MIX_R4_DONE
