# -*- coding: utf-8 -*-
"""模板 + 槽位填充生成微调数据（不使用任何模型输出，尤其不使用 Hy-MT）。
步骤：渲染草稿 → 用 Swift 工具 trip-prompt（App 同一份 PromptBuilder/AmountNormalizer/OutputValidator）
生成提示词并校验 → 去重 → 剔除与 60 条评测用例相近的样本 → 按模板切分 train/valid/test。
用法：python gen.py --per 40 --seed 7 --out ../out
"""
import argparse, json, random, re, subprocess, sys, os, hashlib, collections
sys.path.insert(0, os.path.dirname(__file__))
from templates import T, SLANG, HON, PL, IT, COL, FOOD, FALLBACK_ZH

SCENE_NAME = {"arrival": "机场入境（落地签/海关）", "pickup": "打车/网约车接送", "ride": "打车/网约车接送", "location": "打车/网约车接送",
    "delivery": "外卖（GoFood/GrabFood 骑手聊天）", "restaurant": "餐厅点餐", "shopping": "商店/市场购物付款", "money": "换汇/取款",
    "payment": "商店/市场购物付款", "sim": "电话卡/流量", "hotel": "酒店/别墅前台或房东", "tour": "包车/导游/快艇", "spa": "按摩/SPA",
    "health": "药店/诊所", "emergency": "紧急求助/报警", "directions": "问路", "chat": "日常闲聊"}

def zh_amount(v):
    if v < 10000: return str(v)
    w = v / 10000
    return (f"{w:.1f}".rstrip("0").rstrip(".") if w != int(w) else str(int(w))) + "万"

def dots(v): return f"{v:,}".replace(",", ".")

def amount(kind, rnd):
    if kind == "voa": v = 500000
    elif kind == "tax": v = 150000
    elif kind == "small": v = rnd.choice(list(range(5000, 100000, 5000)) + [12000, 15000, 25000, 35000, 45000, 87000])
    elif kind == "mid": v = rnd.choice(list(range(100000, 1000000, 50000)) + [120000, 175000, 250000])
    else: v = rnd.choice([1000000, 1500000, 2000000, 2500000, 3000000, 5000000, 1200000])
    if v >= 1000000:
        x = v / 1000000; xs = (f"{x:.1f}".rstrip("0").rstrip(".") if x != int(x) else str(int(x)))
        forms = [(f"{xs.replace('.', ',')}jt", None), (f"{xs} juta", f"{xs}百万"), (f"Rp {dots(v)}", None), (f"{xs}jt", None)]
    else:
        n = v // 1000
        forms = [(f"{n}rb", None), (f"{n} ribu", f"{n}千"), (f"{n}k", None), (f"Rp {dots(v)}", None)]
    surf, lit = rnd.choice(forms)
    return v, surf, (lit or surf)

def fill(tpl, slots):
    for k, val in slots.items(): tpl = tpl.replace("{" + k + "}", val)
    return tpl

SL = re.compile(r"«([^»]+)»")

def render(t, rnd, i):
    tid, scene, d, src, lit, tgt, ctx, gloss, kinds = t
    hon = rnd.choice(list(HON)); pl = rnd.choice(list(PL)); it = rnd.choice(list(IT)); col = rnd.choice(list(COL)); food = rnd.choice(list(FOOD))
    lr = rnd.choice([("kiri", "左", "左"), ("kanan", "右", "右")])
    hs = rnd.choice(["1", "2", "3"]); h = rnd.choice(["7", "8", "9", "10"])
    rate = rnd.choice([2550, 2600, 2650, 2300, 2400])
    s = {"HON": hon, "PL": pl, "PLL": PL[pl][0], "PLZ": PL[pl][1], "IT": it, "ITL": IT[it][0], "ITZ": IT[it][1], "COL": col, "COLZ": COL[col],
         "FOOD": food, "FOODZ": FOOD[food], "LR": lr[0], "LRL": lr[1], "LRZ": lr[2], "N": str(rnd.randint(2, 9)), "M": str(rnd.choice([3, 5, 10, 15, 20, 30])),
         "HS": hs, "H": h, "H0": str(int(h) - 1), "D": rnd.choice(["7", "15", "30"]), "G": rnd.choice(["10", "25", "50"]),
         "N2": rnd.choice(["8", "10", "12"]), "M2": rnd.choice(["60", "90", "120"]), "X": rnd.choice(["2", "3"]),
         "RATE": dots(rate), "RATEZ": str(rate)}
    am = [amount(k, rnd) for k in kinds]
    ctx_hon_lit = HON[hon]
    # 俚语：同一词在原文和字面里一致
    choice = {}
    def slang_src(m):
        w = m.group(1)
        if w not in choice:
            if w in SLANG and rnd.random() < 0.6: choice[w] = rnd.choice(SLANG[w][0])
            else: choice[w] = w
        return choice[w]
    def slang_lit(m):
        w = m.group(1); c = choice.get(w, w)
        if c != w: return c
        return SLANG[w][1] if w in SLANG else FALLBACK_ZH.get(w, w)
    src_s = SL.sub(slang_src, src) if d == "them" else src
    lit_s = SL.sub(slang_lit, lit) if d == "them" else lit
    src_s = fill(src_s, s).replace("{HON}", hon)
    lit_s = fill(lit_s.replace("{HON}", ctx_hon_lit), s)
    tgt_s = fill(tgt, s)
    names = ["A", "B"]
    # 上下文里的金额（me 方向和部分 them 方向）
    ctx_out = []
    ai = 0
    for role, o, z in ctx:
        o2 = SL.sub(lambda m: m.group(1), o); z2 = z
        for nm, (v, surf, lt) in zip(names, am):
            if "{" + nm + "}" in o2: o2 = o2.replace("{" + nm + "}", surf); z2 = z2.replace("{" + nm + "}", zh_amount(v))
        o2 = fill(o2, s); z2 = fill(z2, s)
        ctx_out.append({"role": role, "source": o2, "zh": z2} if role == "them" else {"role": "me", "source": o2, "foreign": z2})
    for nm, (v, surf, lt) in zip(names, am):
        src_s = src_s.replace("{" + nm + "}", surf); lit_s = lit_s.replace("{" + nm + "}", lt)
    if d == "them" and rnd.random() < 0.15 and not ctx_out:   # 少量加入无关前文，练习忽略
        ctx_out = [{"role": "me", "source": "你好", "foreign": "Halo"}]
    return {"id": f"{tid}-{i}", "tid": tid, "scene_key": scene, "dir": d, "scene": SCENE_NAME[scene] if rnd.random() < 0.8 else None,
            "context": ctx_out, "source": src_s, "literal": lit_s, "glossary": gloss, "target_template": tgt_s}

def norm_tokens(s): return set(re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]", s.lower()))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--per", type=int, default=40); ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default="../out"); ap.add_argument("--tool", default="../../TripCore/.build/debug/trip-prompt")
    ap.add_argument("--eval", nargs="*", default=["../../docs/model_eval/cases.py", "../../docs/model_eval/cases_ext.py"])
    a = ap.parse_args(); rnd = random.Random(a.seed); os.makedirs(a.out, exist_ok=True)
    drafts, seen = [], set()
    for t in T:
        for i in range(a.per * 3):
            if sum(1 for x in drafts if x["tid"] == t[0]) >= a.per: break
            dft = render(t, rnd, i)
            key = (dft["source"], json.dumps(dft["context"], ensure_ascii=False), dft["scene"])
            if key in seen: continue
            seen.add(key); drafts.append(dft)
    # 评测集去重
    ev = []
    for p in a.eval:
        g = {}; exec(open(p, encoding="utf-8").read(), g)
        ev += [c[3] for c in g.get("C", []) + g.get("C2", [])]
    evt = [norm_tokens(x) for x in ev]
    def near(src):
        t = norm_tokens(src)
        return any(len(t & e) / max(1, len(t | e)) >= 0.6 for e in evt)
    dropped_eval = [d for d in drafts if near(d["source"])]
    drafts = [d for d in drafts if not near(d["source"])]
    # Swift 渲染 + 校验
    inp = "\n".join(json.dumps(d, ensure_ascii=False) for d in drafts) + "\n"
    r = subprocess.run([a.tool], input=inp.encode(), capture_output=True, check=True)
    outs = {o["id"]: o for o in map(json.loads, r.stdout.decode().splitlines())}
    ok, rej = [], collections.Counter()
    for d in drafts:
        o = outs[d["id"]]
        extra = []
        tgt = o["target"]
        if re.search(r"[A-Za-z]{4,}", tgt) and not all(w.lower() in d["source"].lower() for w in re.findall(r"[A-Za-z]{4,}", tgt)): extra.append("latin")
        for am in o["amounts"]:
            if am["display"] not in tgt: extra.append("amount-missing")
        if d["dir"] == "me" and re.findall(r"\d+", tgt) != re.findall(r"\d+", d["source"]): extra.append("me-number-changed")
        if o["validation"] != "accepted" or extra:
            rej[o["validation"] if o["validation"] != "accepted" else extra[0]] += 1; continue
        msgs = [{"role": "system", "content": o["system"]}]
        for u, asst in o["fewshot"]: msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": asst}]
        msgs += [{"role": "user", "content": o["user"]}, {"role": "assistant", "content": tgt}]
        ok.append({"id": d["id"], "tid": d["tid"], "scene": d["scene_key"], "dir": d["dir"], "messages": msgs})
    # 按模板切分：每个场景留 1 个模板做 test（未见模板泛化），其余随机 95/5 分 train/valid
    by_scene = collections.defaultdict(list)
    for t in T: by_scene[t[1]].append(t[0])
    test_t = {rnd.choice(v) for v in by_scene.values() if len(v) >= 3}
    test = [x for x in ok if x["tid"] in test_t]; rest = [x for x in ok if x["tid"] not in test_t]
    rnd.shuffle(rest); nv = max(50, len(rest) // 20)
    split = {"train": rest[nv:], "valid": rest[:nv], "test": test}
    for k, v in split.items():
        with open(f"{a.out}/{k}.jsonl", "w", encoding="utf-8") as f:
            for x in v: f.write(json.dumps({"messages": x["messages"]}, ensure_ascii=False) + "\n")
        with open(f"{a.out}/{k}.meta.jsonl", "w", encoding="utf-8") as f:
            for x in v: f.write(json.dumps({k2: x[k2] for k2 in ("id", "tid", "scene", "dir")}, ensure_ascii=False) + "\n")
    stats = {"drafts": len(drafts) + len(dropped_eval), "dropped_near_eval": len(dropped_eval), "rejected": dict(rej), "kept": len(ok),
             "split": {k: len(v) for k, v in split.items()}, "test_templates": sorted(test_t),
             "by_scene": dict(collections.Counter(x["scene"] for x in ok)), "by_dir": dict(collections.Counter(x["dir"] for x in ok))}
    json.dump(stats, open(f"{a.out}/stats.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(stats, ensure_ascii=False, indent=1))

if __name__ == "__main__": main()
