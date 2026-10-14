# -*- coding: utf-8 -*-
"""P9：生成 印尼语 → 英文理解 的场景数据（模板 + 槽位，不用任何模型输出）。
与 gen.py 相同流程：渲染草稿 → trip-prompt（target=en，App 同一份英文提示词 / 金额换算 / 校验）→ 去重 →
剔除与 docs/model_eval/cases_en.py 相近的样本 → 按模板切分 train/valid/test。
python gen_en.py --per 20 --seed 11 --out ../out_en
"""
import argparse, json, random, re, subprocess, sys, os, collections
sys.path.insert(0, os.path.dirname(__file__))
from templates import T, SLANG, HON, PL, IT, COL, FOOD
from templates_en import EN, SLANG_EN, FALLBACK_EN, HON_EN, PL_EN, IT_EN, COL_EN, FOOD_EN, LR_EN, GLOSS_EN, CTX_EN
from gen import amount, fill, SL, norm_tokens

SCENE_EN = {"arrival": "Airport arrival (visa / customs)", "pickup": "Taxi / ride-hailing pickup", "ride": "Taxi / ride-hailing pickup",
    "location": "Taxi / ride-hailing pickup", "delivery": "Food delivery (rider chat)", "restaurant": "Restaurant ordering",
    "shopping": "Shopping / market payment", "money": "Money exchange / ATM", "payment": "Shopping / market payment", "sim": "SIM card / data",
    "hotel": "Hotel / villa front desk or host", "tour": "Private driver / guide / speedboat", "spa": "Massage / spa",
    "health": "Pharmacy / clinic", "emergency": "Emergency / police", "directions": "Asking directions", "chat": "Small talk"}

def render(t, rnd, i):
    tid, scene, d, src, _lit, _tgt, _ctx, gloss, kinds = t
    lit, tgt = EN[tid]
    hon = rnd.choice(list(HON)); pl = rnd.choice(list(PL)); it = rnd.choice(list(IT)); col = rnd.choice(list(COL)); food = rnd.choice(list(FOOD))
    lr = rnd.choice(["kiri", "kanan"]); hs = rnd.choice(["1", "2", "3"]); h = rnd.choice(["7", "8", "9", "10"])
    rate = rnd.choice([2550, 2600, 2650, 2300, 2400])
    s = {"HON": hon, "PL": pl, "PLE": PL_EN[pl], "IT": it, "ITE": IT_EN[it], "COL": col, "COLE": COL_EN[col], "FOOD": food, "FOODE": FOOD_EN[food],
         "LR": lr, "LRE": LR_EN[lr], "N": str(rnd.randint(2, 9)), "M": str(rnd.choice([3, 5, 10, 15, 20, 30])), "HS": hs, "H": h, "H0": str(int(h) - 1),
         "D": rnd.choice(["7", "15", "30"]), "G": rnd.choice(["10", "25", "50"]), "N2": rnd.choice(["8", "10", "12"]),
         "M2": rnd.choice(["60", "90", "120"]), "X": rnd.choice(["2", "3"]), "RATE": f"{rate:,}".replace(",", "."), "RATEZ": str(rate)}
    am = [amount(k, rnd) for k in kinds]
    choice = {}
    def slang_src(m):
        w = m.group(1)
        if w not in choice: choice[w] = rnd.choice(SLANG[w][0]) if w in SLANG and rnd.random() < 0.6 else w
        return choice[w]
    def slang_lit(m):
        w = m.group(1); c = choice.get(w, w)
        return c if c != w else SLANG_EN.get(w, FALLBACK_EN.get(w, w))
    src_s = fill(SL.sub(slang_src, src), s).replace("{HON}", hon)
    lit_s = fill(SL.sub(slang_lit, lit).replace("{HON}", HON_EN[hon]), s)
    tgt_s = fill(tgt, s)
    ctx_out = []
    for role, o, e in CTX_EN.get(tid, []):
        o2 = SL.sub(lambda m: m.group(1), o); e2 = e
        for nm, (v, surf, _) in zip(["A", "B"], am):
            o2 = o2.replace("{" + nm + "}", surf); e2 = e2.replace("{" + nm + "}", f"Rp {v:,}")
        o2 = fill(o2, s); e2 = fill(e2, s)
        ctx_out.append({"role": "them", "source": o2, "zh": e2} if role == "them" else {"role": "me", "source": o2, "foreign": e2})
    for nm, (v, surf, _) in zip(["A", "B"], am):
        src_s = src_s.replace("{" + nm + "}", surf); lit_s = lit_s.replace("{" + nm + "}", surf)
    if rnd.random() < 0.15 and not ctx_out: ctx_out = [{"role": "me", "source": "Hello", "foreign": "Halo"}]
    gl = [[g[0], GLOSS_EN[g[0]]] for g in gloss if g[0] in GLOSS_EN]
    return {"id": f"en-{tid}-{i}", "tid": tid, "scene_key": scene, "dir": "them", "scene": SCENE_EN[scene] if rnd.random() < 0.8 else None,
            "context": ctx_out, "source": src_s, "literal": lit_s, "glossary": gl, "target_template": tgt_s, "target": "en"}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--per", type=int, default=20); ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", default="../out_en"); ap.add_argument("--tool", default="../../TripCore/.build/debug/trip-prompt")
    ap.add_argument("--eval", nargs="*", default=["../../docs/model_eval/cases_en.py", "../../docs/model_eval/cases.py", "../../docs/model_eval/cases_ext.py"])
    a = ap.parse_args(); rnd = random.Random(a.seed); os.makedirs(a.out, exist_ok=True)
    tpl = [t for t in T if t[2] == "them"]
    drafts, seen = [], set()
    for t in tpl:
        n = 0
        for i in range(a.per * 3):
            if n >= a.per: break
            dft = render(t, rnd, i)
            key = (dft["source"], json.dumps(dft["context"]), dft["scene"])
            if key in seen: continue
            seen.add(key); drafts.append(dft); n += 1
    ev = []
    for p in a.eval:
        g = {}; exec(open(p, encoding="utf-8").read(), g)
        for k in ("C", "C2", "C_EN"): ev += [c[3] for c in g.get(k, [])]
    evt = [norm_tokens(x) for x in ev]
    near = lambda src: any(len(norm_tokens(src) & e) / max(1, len(norm_tokens(src) | e)) >= 0.6 for e in evt)
    dropped = [d for d in drafts if near(d["source"])]; drafts = [d for d in drafts if not near(d["source"])]
    r = subprocess.run([a.tool], input=("\n".join(json.dumps(d, ensure_ascii=False) for d in drafts) + "\n").encode(), capture_output=True, check=True)
    outs = {o["id"]: o for o in map(json.loads, r.stdout.decode().splitlines())}
    ok, rej, rej_ex = [], collections.Counter(), {}
    for d in drafts:
        o = outs[d["id"]]; tgt = o["target"]; extra = []
        if re.search(r"[\u4e00-\u9fff]", tgt): extra.append("han")
        for am in o["amounts"]:
            if am["display_target"] not in tgt: extra.append("amount-missing")
        if o["validation"] != "accepted" or extra:
            k = o["validation"] if o["validation"] != "accepted" else extra[0]; rej[k] += 1; rej_ex.setdefault(k, (d["tid"], d["source"], tgt)); continue
        msgs = [{"role": "system", "content": o["system"]}]
        for u, asst in o["fewshot"]: msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": asst}]
        msgs += [{"role": "user", "content": o["user"]}, {"role": "assistant", "content": tgt}]
        ok.append({"id": d["id"], "tid": d["tid"], "scene": d["scene_key"], "messages": msgs})
    by_scene = collections.defaultdict(list)
    for t in tpl: by_scene[t[1]].append(t[0])
    test_t = {rnd.choice(v) for v in by_scene.values() if len(v) >= 3}
    test = [x for x in ok if x["tid"] in test_t]; rest = [x for x in ok if x["tid"] not in test_t]
    rnd.shuffle(rest); nv = max(30, len(rest) // 20)
    split = {"train": rest[nv:], "valid": rest[:nv], "test": test}
    for k, v in split.items():
        with open(f"{a.out}/{k}.jsonl", "w", encoding="utf-8") as f:
            for x in v: f.write(json.dumps({"messages": x["messages"]}, ensure_ascii=False) + "\n")
    stats = {"drafts": len(drafts) + len(dropped), "dropped_near_eval": len(dropped), "rejected": dict(rej), "rejected_examples": rej_ex,
             "kept": len(ok), "split": {k: len(v) for k, v in split.items()}, "test_templates": sorted(test_t)}
    json.dump(stats, open(f"{a.out}/stats.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(stats, ensure_ascii=False, indent=1))

if __name__ == "__main__": main()
