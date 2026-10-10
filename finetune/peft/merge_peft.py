# 合并 LoRA → 完整 HF 权重（fp16），供 llama.cpp 转 GGUF
import argparse, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
ap = argparse.ArgumentParser(); ap.add_argument("--base", required=True); ap.add_argument("--lora", required=True); ap.add_argument("--out", required=True)
a = ap.parse_args()
m = AutoModelForCausalLM.from_pretrained(a.base, torch_dtype=torch.float16)
m = PeftModel.from_pretrained(m, a.lora).merge_and_unload()
m.save_pretrained(a.out, safe_serialization=True); AutoTokenizer.from_pretrained(a.base).save_pretrained(a.out)
print("merged ->", a.out)
