#!/bin/bash
source /workspace/venv/bin/activate 2>/dev/null
M=/workspace/models
for m in a a2 b; do python hymt_eval.py $M/HY-MT1.5-1.8B-Q4_K_M.gguf $m > log_hymt_q4_$m.txt 2>&1; done
python hymt_eval.py $M/HY-MT1.5-1.8B-Q4_K_M.gguf c $M/qwen2.5-1.5b-instruct-q4_k_m.gguf > log_hymt_q4_c.txt 2>&1
echo ALLDONE > hymt_done.flag
