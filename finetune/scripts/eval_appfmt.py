# -*- coding: utf-8 -*-
"""用 App 同一份提示词（trip-prompt 渲染）在 60 条评测用例上打分。
评分与端侧模型验证报告一致：关键词分（每条 0/1/2）、严格分（中文金额写错即 0）。
另报告「App 校验通过率」：输出再经 OutputValidator，被 App 接受（会替换字面）的比例。
python scripts/eval_appfmt.py <gguf> [--limit N]   （CPU 速度，非 iPhone）
"""
import argparse, json, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "docs", "model_eval"))
from cases import C
from cases_ext import C2
from run import score, valid
TOOL = os.path.join(ROOT, "TripCore", ".build", "debug", "trip-prompt")

def drafts(cases, outs=None):
    ds = []
    for k, c in enumerate(cases):
        ctx = [{"role": "them", "source": o, "zh": z} if r == "them" else ({"role": "me", "source": o, "foreign": z} if z else {"role": "me", "source": o}) for r, o, z in c[2]]
        gl = [g.split("=", 1) for g in c[5] if "=" in g]
        ds.append({"id": c[0], "context": ctx, "source": c[3], "literal": c[4], "glossary": gl, "target_template": (outs[k] if outs else "x") or "x"})
    return ds

def render(ds):
    r = subprocess.run([TOOL], input=("\n".join(json.dumps(d, ensure_ascii=False) for d in ds) + "\n").encode(), capture_output=True, check=True)
    return [json.loads(l) for l in r.stdout.decode().splitlines()]

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("gguf"); ap.add_argument("--limit", type=int, default=0); ap.add_argument("--tag", default="")
    a = ap.parse_args()
    from llama_cpp import Llama
    cases = (C + C2)[: a.limit or None]
    rendered = render(drafts(cases))
    llm = Llama(a.gguf, n_ctx=2048, n_threads=8, verbose=False)
    outs, res = [], []
    for c, o in zip(cases, rendered):
        msgs = [{"role": "system", "content": o["system"]}]
        for u, asst in o["fewshot"]: msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": asst}]
        msgs.append({"role": "user", "content": o["user"]})
        t0 = time.time(); first = None; out = ""
        for ch in llm.create_chat_completion(msgs, temperature=0, max_tokens=80, stream=True):
            d = ch["choices"][0]["delta"].get("content")
            if d: first = first or time.time(); out += d
        out = out.strip().split("\n")[0].strip().strip('"「」')
        outs.append(out)
        ok_w = [k for grp in c[6] for k in grp if "万" in k]
        s = score(out, c)[0]; ws = re.findall(r"(\d+(?:\.\d+)?)万", out)
        amount_err = bool(ws and ok_w and any(f"{w}万" not in ok_w for w in ws))
        st = 0 if amount_err else (min(s, 1) if not valid(out) else s)
        res.append({"id": c[0], "src": c[3], "out": out, "score": s, "strict": st, "amount_err": amount_err, "ttft": round((first or time.time()) - t0, 3)})
        print(c[0], s, st, out, flush=True)
    for r, v in zip(res, render(drafts(cases, outs))): r["app_validation"] = v["validation"]
    n = len(res); half = lambda ids: [r for r in res if (int(r["id"]) <= 30) == ids]
    sm = {"model": os.path.basename(a.gguf), "tag": a.tag, "n": n, "score": sum(r["score"] for r in res), "strict": sum(r["strict"] for r in res), "max": 2 * n,
          "orig30_strict": sum(r["strict"] for r in half(True)), "ext30_strict": sum(r["strict"] for r in half(False)),
          "amount_err": sum(r["amount_err"] for r in res), "app_accepted": sum(r["app_validation"] == "accepted" for r in res),
          "ttft_med": sorted(r["ttft"] for r in res)[n // 2]}
    out = os.path.join(os.getcwd(), f"eval_{a.tag or os.path.basename(a.gguf)}.json")
    json.dump({"summary": sm, "results": res}, open(out, "w"), ensure_ascii=False, indent=1); print(sm)

if __name__ == "__main__": main()
