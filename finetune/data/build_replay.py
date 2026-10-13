# -*- coding: utf-8 -*-
"""通用能力回放数据（防灾难性遗忘；Mac run r1/r2：LoRA 后公开集 chrF 大幅下降）。
来源（需先 public_data/fetch.sh）：Tatoeba ind↔cmn（CC BY 2.0 FR）、STIF-Indonesia **train**（MIT）、FLORES-200 **dev**（CC BY-SA 4.0；评测只用 devtest）。
r4：Mac run r3 显示 mt_id_en 掉得最多（无英文回放），加入 FLORES dev 的 印→中 与 印→英。
与评测集严格不相交：排除 public_eval.jsonl 中出现的所有原文（规范化后比较）；不用 FLORES devtest、Wikivoyage、STIF test/dev。
提示词与 scripts/eval_public.py 相同（通用翻译 / 口语规范化），这是「保持原有能力」，不是针对评测句训练。
输出 out_mix/{train,valid}.jsonl = out/ 的场景数据 + 回放（默认回放占约 45%）；test.jsonl 复制自 out/。
python data/build_replay.py [--ratio 0.3] [--seed 0]
"""
import argparse, json, os, random, re, shutil
H = os.path.dirname(os.path.abspath(__file__)); F = os.path.join(H, "..")
R = os.path.join(F, "public_data", "raw")
SYS = "你是翻译助手。只输出译文一行，不要解释。"
P_ZH = "把下面的印尼语翻译成简体中文：\n{src}"
P_EN = "Translate the following Indonesian into English:\n{src}"
P_NORM = "把下面的印尼语口语/网络缩写改写成规范的正式印尼语（仍然是印尼语，不要翻译）：\n{src}"
norm = lambda s: re.sub(r"\W+", " ", s.lower()).strip()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--ratio", type=float, default=0.45); ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args(); rnd = random.Random(a.seed)
    banned = {norm(json.loads(l)["src"]) for l in open(os.path.join(F, "public_data", "public_eval.jsonl"), encoding="utf-8")}
    try:
        import opencc; t2s = opencc.OpenCC("t2s").convert
    except Exception: t2s = lambda x: x
    ind = {}; cmn = {}
    for l in open(f"{R}/ind_sentences.tsv", encoding="utf-8"): i, _, t = l.rstrip("\n").split("\t", 2); ind[i] = t
    for l in open(f"{R}/cmn_sentences.tsv", encoding="utf-8"): i, _, t = l.rstrip("\n").split("\t", 2); cmn[i] = t
    rep = []; seen = set()
    for l in open(f"{R}/ind-cmn_links.tsv", encoding="utf-8"):
        x, y = l.split()[:2]
        if x in ind and y in cmn and x not in seen and norm(ind[x]) not in banned:
            seen.add(x); rep.append(("mt", ind[x], t2s(cmn[y])))
    inf = open(f"{R}/stif_train.inf", encoding="utf-8").read().splitlines(); frm = open(f"{R}/stif_train.for", encoding="utf-8").read().splitlines()
    for s, t in zip(inf, frm):
        if s.strip() and t.strip() and norm(s) not in banned and norm(s) != norm(t): rep.append(("norm", s.strip(), t.strip()))
    fd = os.path.join(R, "flores200_dataset", "dev")
    if os.path.isdir(fd):
        fi = open(f"{fd}/ind_Latn.dev", encoding="utf-8").read().splitlines()
        fz = open(f"{fd}/zho_Hans.dev", encoding="utf-8").read().splitlines()
        fe = open(f"{fd}/eng_Latn.dev", encoding="utf-8").read().splitlines()
        for k, (i_, z_, e_) in enumerate(zip(fi, fz, fe)):
            if norm(i_) in banned: continue
            rep.append(("mt", i_, z_) if k % 2 == 0 else ("en", i_, e_))   # 一半到中文、一半到英文
    rnd.shuffle(rep)
    def ex(k, s, t): return {"messages": [{"role": "system", "content": SYS}, {"role": "user", "content": {"mt": P_ZH, "en": P_EN, "norm": P_NORM}[k].format(src=s)}, {"role": "assistant", "content": t}]}
    out = os.path.join(F, "out_mix"); os.makedirs(out, exist_ok=True)
    train = [json.loads(l) for l in open(os.path.join(F, "out", "train.jsonl"), encoding="utf-8")]
    valid = [json.loads(l) for l in open(os.path.join(F, "out", "valid.jsonl"), encoding="utf-8")]
    n_tr = min(len(rep) - 60, int(len(train) * a.ratio / (1 - a.ratio)))
    rv, rt = rep[:60], rep[60:60 + n_tr]
    mix_t = train + [ex(*r) for r in rt]; mix_v = valid + [ex(*r) for r in rv]
    rnd.shuffle(mix_t); rnd.shuffle(mix_v)
    for n, d in [("train", mix_t), ("valid", mix_v)]:
        with open(os.path.join(out, f"{n}.jsonl"), "w", encoding="utf-8") as f:
            for e in d: f.write(json.dumps(e, ensure_ascii=False) + "\n")
    shutil.copy(os.path.join(F, "out", "test.jsonl"), os.path.join(out, "test.jsonl"))
    st = {"scene_train": len(train), "replay_train": len(rt), "replay_valid": len(rv),
          "replay_mt": sum(r[0] == "mt" for r in rt), "replay_norm": sum(r[0] == "norm" for r in rt), "replay_en": sum(r[0] == "en" for r in rt), "banned_eval_src": len(banned)}
    json.dump(st, open(os.path.join(out, "stats.json"), "w"), indent=1); print(st)

if __name__ == "__main__": main()
