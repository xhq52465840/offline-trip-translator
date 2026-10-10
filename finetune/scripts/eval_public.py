# -*- coding: utf-8 -*-
"""公开来源评测（public_data/public_eval.jsonl）：GGUF + llama-cpp-python 生成，chrF++（sacrebleu）按来源/任务汇总。
任务：mt_id_zh 印→中（对中文参考）；mt_id_en 印→英（对英文参考）；slang_norm 口语→正式印尼语（对正式参考）。
CPU 速度非 iPhone。COMET 默认关闭（--comet 打开，需 pip install unbabel-comet，约 2–3 GB 内存）。
python scripts/eval_public.py <model.gguf> --tag base [--limit N] [--tasks mt_id_zh,mt_id_en,slang_norm] [--comet]
"""
import argparse, json, os, sys, time, collections
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "public_data", "public_eval.jsonl")
SYS = "你是翻译助手。只输出译文一行，不要解释。"
PROMPT = {
    "mt_id_zh": "把下面的印尼语翻译成简体中文：\n{src}",
    "mt_id_en": "Translate the following Indonesian into English:\n{src}",
    "slang_norm": "把下面的印尼语口语/网络缩写改写成规范的正式印尼语（仍然是印尼语，不要翻译）：\n{src}",
}
REF = {"mt_id_zh": "ref_zh", "mt_id_en": "ref_en", "slang_norm": "ref_id_formal"}

def chrfpp(hyps, refs, zh=False):
    from sacrebleu.metrics import CHRF
    m = CHRF(word_order=0 if zh else 2)   # 中文无空格分词：用字符级 chrF（word_order=0）；其余 chrF++
    return round(m.corpus_score(hyps, [refs]).score, 2)

def summarize(rows):
    groups = collections.defaultdict(list)
    for r in rows:
        groups[("task", r["task"])].append(r); groups[("source", r["source_dataset"] + "/" + r["task"])].append(r)
    out = {}
    for (kind, k), rs in sorted(groups.items()):
        out[f"{kind}:{k}"] = {"n": len(rs), "chrf": chrfpp([r["hyp"] for r in rs], [r["ref"] for r in rs], zh=rs[0]["task"] == "mt_id_zh")}
    return out

def clean(s):
    s = s.strip().split("\n")[0].strip()
    return s.strip('"「」')

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("gguf"); ap.add_argument("--tag", default=""); ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tasks", default="mt_id_zh,mt_id_en,slang_norm"); ap.add_argument("--comet", action="store_true"); ap.add_argument("--threads", type=int, default=4)
    a = ap.parse_args()
    tasks = set(a.tasks.split(","))
    items = [json.loads(l) for l in open(DATA, encoding="utf-8")]
    items = [x for x in items if x["task"] in tasks]
    if a.limit:  # 每个任务各取前 limit 条
        c = collections.Counter(); keep = []
        for x in items:
            if c[x["task"]] < a.limit: keep.append(x); c[x["task"]] += 1
        items = keep
    from llama_cpp import Llama
    llm = Llama(a.gguf, n_ctx=1024, n_threads=a.threads, verbose=False)
    rows = []
    for x in items:
        t0 = time.time()
        r = llm.create_chat_completion([{"role": "system", "content": SYS}, {"role": "user", "content": PROMPT[x["task"]].format(src=x["src"])}],
                                       temperature=0, max_tokens=160)
        hyp = clean(r["choices"][0]["message"]["content"])
        rows.append({"id": x["id"], "task": x["task"], "source_dataset": x["source_dataset"], "scene": x["scene"], "src": x["src"],
                     "ref": x[REF[x["task"]]], "hyp": hyp, "sec": round(time.time() - t0, 2)})
        print(x["id"], x["task"], "|", hyp, flush=True)
    summ = summarize(rows)
    if a.comet:
        from comet import download_model, load_from_checkpoint
        cm = load_from_checkpoint(download_model("Unbabel/wmt22-comet-da"))
        mt = [r for r in rows if r["task"] != "slang_norm"]
        sc = cm.predict([{"src": r["src"], "mt": r["hyp"], "ref": r["ref"]} for r in mt], batch_size=8, gpus=0).scores
        for r, s in zip(mt, sc): r["comet"] = s
        summ["comet:mt"] = {"n": len(mt), "comet": round(sum(sc) / max(1, len(sc)), 4)}
    res = {"model": os.path.basename(a.gguf), "tag": a.tag, "n": len(rows), "summary": summ, "rows": rows}
    os.makedirs(os.path.join(HERE, "..", "results"), exist_ok=True)
    p = os.path.join(HERE, "..", "results", f"public_{a.tag or os.path.basename(a.gguf)}.json")
    json.dump(res, open(p, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(summ, ensure_ascii=False, indent=1)); print("->", p)

if __name__ == "__main__": main()
