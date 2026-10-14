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
from cases_en import C_EN
EN_SLANG = {"rb", "jt", "udh", "udah", "gk", "gak", "nggak", "sy", "bs", "brp", "blm", "lg", "mnt", "bgt", "sdh", "pake", "aja", "kak", "yg"}
EN_AMT = re.compile(r"(?<![\w.,])(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?\s*(?:k|thousand|million|mil|m)\b|\d{4,})", re.I)
def en_val(s):
    t = s.lower().replace(" ", "")
    for suf, mul in (("thousand", 1e3), ("million", 1e6), ("mil", 1e6), ("k", 1e3), ("m", 1e6)):
        if t.endswith(suf):
            try: return int(round(float(t[: -len(suf)]) * mul))
            except ValueError: return None
    try: return int(t.replace(",", ""))
    except ValueError: return None
def score_en(out, c):
    o = out.lower(); g, forb = c[6], c[7]
    hit = sum(any(k.lower() in o for k in grp) for grp in g)
    words = re.findall(r"[a-z']+", o); bad = any(f.lower() in words or f.lower() in o.split() for f in forb)
    return (2 if hit == len(g) and not bad else (1 if hit * 2 >= len(g) and not bad else 0)), hit, bad
def valid_en(out):
    return bool(out) and not re.search(r"[\u4e00-\u9fff]", out) and len(out.split()) <= 60 and not (set(re.findall(r"[a-z]+", out.lower())) & EN_SLANG)
def amount_err_en(out, c):
    ok = {v for grp in c[6] for k in grp for v in [en_val(m) for m in EN_AMT.findall(k)] if v}
    if not ok: return False
    got = [en_val(m) for m in EN_AMT.findall(out)]
    return any(v and v >= 1000 and v not in ok for v in got)
TOOL = os.path.join(ROOT, "TripCore", ".build", "debug", "trip-prompt")

def drafts(cases, outs=None, target=None):
    ds = []
    for k, c in enumerate(cases):
        ctx = [{"role": "them", "source": o, "zh": z} if r == "them" else ({"role": "me", "source": o, "foreign": z} if z else {"role": "me", "source": o}) for r, o, z in c[2]]
        gl = [g.split("=", 1) for g in c[5] if "=" in g]
        ds.append({"id": c[0], "context": ctx, "source": c[3], "literal": c[4], "glossary": gl, "target_template": (outs[k] if outs else "x") or "x", **({"target": target} if target else {})})
    return ds

def render(ds):
    r = subprocess.run([TOOL], input=("\n".join(json.dumps(d, ensure_ascii=False) for d in ds) + "\n").encode(), capture_output=True, check=True)
    return [json.loads(l) for l in r.stdout.decode().splitlines()]

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("gguf"); ap.add_argument("--limit", type=int, default=0); ap.add_argument("--tag", default="")
    ap.add_argument("--target", default="zh-Hans", choices=["zh-Hans", "en"], help="en = id→en 理解评测（cases_en.py，P3）")
    a = ap.parse_args()
    en = a.target == "en"
    from llama_cpp import Llama
    cases = (C_EN if en else C + C2)[: a.limit or None]
    rendered = render(drafts(cases, target=a.target if en else None))
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
        if en:
            s = score_en(out, c)[0]; amount_err = amount_err_en(out, c)
            st = 0 if amount_err else (min(s, 1) if not valid_en(out) else s)
        else:
            ok_w = [k for grp in c[6] for k in grp if "万" in k]
            s = score(out, c)[0]; ws = re.findall(r"(\d+(?:\.\d+)?)万", out)
            amount_err = bool(ws and ok_w and any(f"{w}万" not in ok_w for w in ws))
            st = 0 if amount_err else (min(s, 1) if not valid(out) else s)
        res.append({"id": c[0], "src": c[3], "out": out, "score": s, "strict": st, "amount_err": amount_err, "ttft": round((first or time.time()) - t0, 3)})
        print(c[0], s, st, out, flush=True)
    for r, v in zip(res, render(drafts(cases, outs, target=a.target if en else None))): r["app_validation"] = v["validation"]
    n = len(res); half = lambda ids: [r for r in res if (int(r["id"]) <= 30) == ids]
    sm = {"model": os.path.basename(a.gguf), "tag": a.tag, "target": a.target, "n": n, "score": sum(r["score"] for r in res), "strict": sum(r["strict"] for r in res), "max": 2 * n,
          "orig30_strict": sum(r["strict"] for r in half(True)), "ext30_strict": sum(r["strict"] for r in half(False)),
          "amount_err": sum(r["amount_err"] for r in res), "app_accepted": sum(r["app_validation"] == "accepted" for r in res),
          "ttft_med": sorted(r["ttft"] for r in res)[n // 2]}
    out = os.path.join(os.getcwd(), f"eval_{a.tag or os.path.basename(a.gguf)}.json")
    json.dump({"summary": sm, "results": res}, open(out, "w"), ensure_ascii=False, indent=1); print(sm)

if __name__ == "__main__": main()
