# -*- coding: utf-8 -*-
"""LoRA 微调（PyTorch + PEFT）。CUDA 首选；也能在 CPU 上跑冒烟。
只对最后一条 assistant（理解输出）计算 loss；提示词格式与 App 完全一致（system + few-shot + user）。
python peft/train_peft.py --model Qwen/Qwen2.5-1.5B-Instruct --data out --out runs/lora --steps 600
"""
import argparse, json, math, os, random, time
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, get_cosine_schedule_with_warmup
from peft import LoraConfig, get_peft_model

ap = argparse.ArgumentParser()
ap.add_argument("--model", default="Qwen/Qwen2.5-1.5B-Instruct"); ap.add_argument("--data", default="out"); ap.add_argument("--out", default="runs/lora")
ap.add_argument("--steps", type=int, default=600); ap.add_argument("--bs", type=int, default=4); ap.add_argument("--grad_accum", type=int, default=4)
ap.add_argument("--lr", type=float, default=2e-4); ap.add_argument("--rank", type=int, default=16); ap.add_argument("--alpha", type=int, default=32)
ap.add_argument("--max_len", type=int, default=768); ap.add_argument("--limit", type=int, default=0, help="只用前 N 条（冒烟）")
ap.add_argument("--eval_every", type=int, default=100); ap.add_argument("--seed", type=int, default=0); ap.add_argument("--threads", type=int, default=0)
a = ap.parse_args()
random.seed(a.seed); torch.manual_seed(a.seed)
if a.threads: torch.set_num_threads(a.threads)
dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
dtype = torch.bfloat16 if dev == "cuda" else torch.float32
tok = AutoTokenizer.from_pretrained(a.model)
model = AutoModelForCausalLM.from_pretrained(a.model, torch_dtype=dtype).to(dev)
model.gradient_checkpointing_enable(); model.enable_input_require_grads()
model = get_peft_model(model, LoraConfig(r=a.rank, lora_alpha=a.alpha, lora_dropout=0.05, task_type="CAUSAL_LM",
                                         target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]))
model.print_trainable_parameters()

def encode(ex):
    msgs = ex["messages"]
    prompt = tok.apply_chat_template(msgs[:-1], tokenize=False, add_generation_prompt=True)
    full = prompt + msgs[-1]["content"] + "<|im_end|>\n"
    p_ids = tok(prompt, add_special_tokens=False)["input_ids"]; ids = tok(full, add_special_tokens=False)["input_ids"][: a.max_len]
    labels = [-100] * min(len(p_ids), len(ids)) + ids[len(p_ids):]
    return ids, labels[: len(ids)]

def load(split):
    p = os.path.join(a.data, f"{split}.jsonl")
    xs = [json.loads(l) for l in open(p, encoding="utf-8")]
    return [encode(x) for x in (xs[: a.limit] if a.limit else xs)]

train = load("train"); valid = load("valid")[:64]
print(f"device={dev} train={len(train)} valid={len(valid)} max_tokens={max(len(i) for i, _ in train)}")

def batch(items):
    L = max(len(i) for i, _ in items); pad = tok.pad_token_id or tok.eos_token_id
    ids = torch.tensor([i + [pad] * (L - len(i)) for i, _ in items]); lab = torch.tensor([l + [-100] * (L - len(l)) for _, l in items])
    att = torch.tensor([[1] * len(i) + [0] * (L - len(i)) for i, _ in items])
    return ids.to(dev), att.to(dev), lab.to(dev)

@torch.no_grad()
def val_loss():
    model.eval(); tot = 0.0
    for k in range(0, len(valid), a.bs):
        i, m, l = batch(valid[k:k + a.bs]); tot += model(input_ids=i, attention_mask=m, labels=l).loss.item() * len(valid[k:k + a.bs])
    model.train(); return tot / max(1, len(valid))

opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=a.lr, weight_decay=0.0)
sch = get_cosine_schedule_with_warmup(opt, max(1, a.steps // 20), a.steps)
log = []; t0 = time.time(); order = []
print(f"step 0 val_loss {val_loss():.4f}")
model.train()
for step in range(1, a.steps + 1):
    for _ in range(a.grad_accum):
        if not order: order = list(range(len(train))); random.shuffle(order)
        idx = [order.pop() for _ in range(min(a.bs, len(order)))]
        i, m, l = batch([train[j] for j in idx])
        (model(input_ids=i, attention_mask=m, labels=l).loss / a.grad_accum).backward()
    torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step(); sch.step(); opt.zero_grad()
    if step % max(1, a.steps // 20) == 0 or step == 1:
        print(f"step {step} lr {sch.get_last_lr()[0]:.2e} {(time.time()-t0)/step:.1f}s/step", flush=True)
    if step % a.eval_every == 0 or step == a.steps:
        v = val_loss(); log.append({"step": step, "val_loss": v, "elapsed_s": round(time.time() - t0)}); print(f"step {step} val_loss {v:.4f}", flush=True)
model.save_pretrained(a.out); tok.save_pretrained(a.out)
json.dump({"args": vars(a), "log": log, "device": dev}, open(os.path.join(a.out, "train_log.json"), "w"), indent=1)
