# -*- coding: utf-8 -*-
"""P9：out_mix3 = out_mix（中文目标场景 + 通用回放，r4 采用 s400 的数据）+ out_en（英文目标场景，gen_en.py）。
python data/build_mix3.py [--seed 0]   → out_mix3/{train,valid,test}.jsonl + stats.json
"""
import argparse, json, os, random
H = os.path.dirname(os.path.abspath(__file__)); F = os.path.join(H, "..")
def rd(p): return [l for l in open(p, encoding="utf-8") if l.strip()]
ap = argparse.ArgumentParser(); ap.add_argument("--seed", type=int, default=0); a = ap.parse_args(); rnd = random.Random(a.seed)
out = os.path.join(F, "out_mix3"); os.makedirs(out, exist_ok=True); st = {}
for k in ("train", "valid", "test"):
    zh = rd(os.path.join(F, "out_mix", f"{k}.jsonl")); en = rd(os.path.join(F, "out_en", f"{k}.jsonl"))
    rows = zh + en; rnd.shuffle(rows)
    open(os.path.join(out, f"{k}.jsonl"), "w", encoding="utf-8").writelines(rows)
    st[k] = {"zh_mix": len(zh), "en_scene": len(en), "total": len(rows), "en_share": round(len(en) / len(rows), 3)}
json.dump(st, open(os.path.join(out, "stats.json"), "w"), indent=1); print(json.dumps(st))
