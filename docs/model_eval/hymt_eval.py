"""Hy-MT1.5-1.8B 评测：a=直译(替代系统翻译) a2=官方上下文翻译模板 b=我们的理解提示词 c=Hy-MT直译+Qwen2.5-1.5B理解
用法: python hymt_eval.py <gguf|http://host:port> <mode> [qwen_gguf]
CPU 数据，非 iPhone 速度。temperature=0（为可复现；官方推荐 0.7/top_p0.6）。"""
import sys,time,json,re,os,urllib.request
from cases import C
import run
from rescore import strict, OK

ZH="将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\n{src}"
CTX="{ctx}\n参考上面的信息，把下面的文本翻译成中文，注意不需要翻译上文，也不要额外解释：\n{src}\n"
TERM="参考下面的翻译：\n{terms}\n\n将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n{src}"

class Py:
    def __init__(s,path):
        from llama_cpp import Llama
        t=time.time(); s.l=Llama(path,n_ctx=2048,n_threads=8,verbose=False); s.load=time.time()-t
        s.name=os.path.basename(path); s.size=os.path.getsize(path)
    def chat(s,m,max_tokens=80):
        t0=time.time(); first=None; n=0; out=""
        for ch in s.l.create_chat_completion(m,temperature=0,max_tokens=max_tokens,stream=True):
            d=ch["choices"][0]["delta"].get("content")
            if d:
                first=first or time.time(); n+=1; out+=d
        return out,t0,first,n,time.time()
class Srv:
    def __init__(s,url,name,size): s.url=url; s.name=name; s.size=size; s.load=None
    def chat(s,m,max_tokens=80):
        body=json.dumps(dict(messages=m,temperature=0,max_tokens=max_tokens,stream=True)).encode()
        req=urllib.request.Request(s.url+"/v1/chat/completions",body,{"Content-Type":"application/json"})
        t0=time.time(); first=None; n=0; out=""
        with urllib.request.urlopen(req) as r:
            for line in r:
                line=line.decode().strip()
                if not line.startswith("data:") or line.endswith("[DONE]"): continue
                d=json.loads(line[5:])["choices"][0]["delta"].get("content")
                if d: first=first or time.time(); n+=1; out+=d
        return out,t0,first,n,time.time()

def ctxtext(c):
    return "\n".join((f"对方：{o}（{z}）" if z else f"对方：{o}") if r=="them" else f"我：{o}" for r,o,z in c[2])

def build(mode,c):
    if mode=="a": return [{"role":"user","content":ZH.format(src=c[3])}]
    if mode=="a2":
        terms="\n".join(f"{g.split('=')[0]} 翻译成 {g.split('=')[1]}" for g in c[5])
        ctx=ctxtext(c)
        if ctx: return [{"role":"user","content":CTX.format(ctx=("参考翻译：\n"+terms+"\n" if terms else "")+ctx,src=c[3])}]
        return [{"role":"user","content":(TERM.format(terms=terms,src=c[3]) if terms else ZH.format(src=c[3]))}]
    if mode=="b": return run.msgs(c,False)

def clean(o): return re.sub(r"<think>.*?</think>","",o,flags=re.S).strip().split("\n")[0].strip().strip('"「」')

def amount_err(r):
    ws=re.findall(r'(\d+(?:\.\d+)?)万',r["out"])
    return bool(ws and OK.get(r["id"]) and any(f"{w}万" not in OK[r["id"]] for w in ws))

def main():
    tgt,mode=sys.argv[1],sys.argv[2]
    eng=Srv(tgt,sys.argv[4] if len(sys.argv)>4 else "server",int(sys.argv[5]) if len(sys.argv)>5 else 0) if tgt.startswith("http") else Py(tgt)
    q=Py(sys.argv[3]) if mode=="c" else None
    res=[]
    for c in C:
        if mode=="c":
            lit,t0,f,n,e=eng.chat(build("a",c)); lit=clean(lit)
            cc=list(c); cc[4]=lit
            out,t1,f2,n2,e2=q.chat(run.msgs(tuple(cc),False))
            r=dict(id=c[0],cat=c[1],src=c[3],literal=lit,out=clean(out),ttft=round((f2 or e2)-t0,3),hy_total=round(e-t0,3),qwen_ttft=round((f2 or e2)-t1,3),gen_tps=round((n2-1)/max(e2-f2,1e-6),1) if f2 and n2>1 else None)
        else:
            out,t0,f,n,e=eng.chat(build(mode,c))
            r=dict(id=c[0],cat=c[1],src=c[3],out=clean(out),ttft=round((f or e)-t0,3),total=round(e-t0,3),gen_tps=round((n-1)/max(e-f,1e-6),1) if f and n>1 else None)
        r["score"]=run.score(r["out"],c)[0]; r["valid"]=run.valid(r["out"]); r["strict"]=strict(r); r["amount_err"]=amount_err(r)
        res.append(r); print(c[0],r["score"],r["strict"],r["out"],r["ttft"],flush=True)
    med=lambda k:sorted((x.get(k) or 0) for x in res)[15]
    sm=dict(model=eng.name,mode=mode,size_mb=round(eng.size/1e6),load_s=eng.load and round(eng.load,2),score=sum(x["score"] for x in res),strict=sum(x["strict"] for x in res),
            full=sum(x["score"]==2 for x in res),valid=sum(x["valid"] for x in res),amount_err=sum(x["amount_err"] for x in res),ttft_med=med("ttft"),total_med=med("total") if mode!="c" else med("hy_total"),tps_med=med("gen_tps"))
    json.dump(dict(summary=sm,results=res),open(f"hymt_{eng.name}_{mode}.json","w"),ensure_ascii=False,indent=1); print(sm)
main()
