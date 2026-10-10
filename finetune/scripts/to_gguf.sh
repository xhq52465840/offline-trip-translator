#!/usr/bin/env bash
# HF 权重目录 → GGUF f16 → Q4_K_M，并输出 sha256 / 字节数（填入 model-manifest.json）
# 用法：scripts/to_gguf.sh <hf_dir> <out_prefix>
set -euo pipefail
HF=$1; OUT=$2; LLAMA_CPP=${LLAMA_CPP:-$HOME/llama.cpp}
QUANT=${QUANT:-$(ls "$LLAMA_CPP"/build*/bin/llama-quantize 2>/dev/null | head -1)}
python "$LLAMA_CPP/convert_hf_to_gguf.py" "$HF" --outtype f16 --outfile "$OUT-f16.gguf"
"$QUANT" "$OUT-f16.gguf" "$OUT-Q4_K_M.gguf" Q4_K_M
rm -f "$OUT-f16.gguf"
python - "$OUT-Q4_K_M.gguf" <<'PY'
import hashlib, os, sys, json
p = sys.argv[1]; h = hashlib.sha256()
with open(p, "rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
info = {"file": os.path.basename(p), "bytes": os.path.getsize(p), "sha256": h.hexdigest()}
json.dump(info, open(p + ".json", "w"), indent=1); print(json.dumps(info, indent=1))
PY
