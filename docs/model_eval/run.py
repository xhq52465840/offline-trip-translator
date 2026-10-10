import sys,time,json,re,os
from llama_cpp import Llama
from cases import C
if os.environ.get('CASES')=='ext':
    from cases_ext import C2 as C
SYS="""你是旅行对话的中文译文修正器。游客是中国人，对方说印尼语或英语。你只修改「字面」这句中文译文，让它符合这场对话和原文真实意思：
- 把印尼语/英语缩写俚语译对（brp=berapa多少, gk/nggak=不, udh/udah=已经, sy=我, bs=bisa可以, otw/omw=在路上, mnt=分钟, lg=lagi再/还, aja=就, kak/pak=称呼可省略）。
- 金额：rb/ribu=千，jt/juta=百万，换成中文万，如50rb=5万，1,5jt=150万。上下文在讲价时，没单位的数字如40通常指4万。
- 把「刚才那个」「那里」等指代说清楚是什么。
- 不要写印尼语或英语单词，不要解释。只输出一行中文。"""
FEW=[("对方：harga 30rb ／ 中文：价格3万\n我：太贵了","词：无","对方原文：yang tadi 25 aja","刚才的25就行","刚才那个价格2.5万就行"),
("（无）","词：无","对方原文：udh sampe blm?","udh sampe blm？","已经到了吗？")]
def prompt(c):
    _,_,ctx,src,lit,gl,_,_=c
    lines=[]
    for r,o,z in ctx:
        lines.append(f"对方：{o} ／ 中文：{z}" if r=="them" else f"我：{o}")
    return "这场对话（时间顺序）：\n"+("\n".join(lines) or "（无）")+"\n\n词：\n"+(", ".join(g.replace("="," = ") for g in gl) or "无")+f"\n\n对方原文：{src}\n字面：\n{lit}"
def msgs(c,nothink):
    m=[{"role":"system","content":SYS}]
    for ctx,gl,src,lit,out in FEW:
        m+=[{"role":"user","content":f"这场对话（时间顺序）：\n{ctx}\n\n{gl}\n\n{src}\n字面：\n{lit}"},{"role":"assistant","content":out}]
    m.append({"role":"user","content":prompt(c)+(" /no_think" if nothink else "")})
    return m
def score(out,c):
    g,forb=c[6],c[7]
    hit=sum(any(k in out for k in grp) for grp in g)
    bad=any(f in out for f in forb)
    s=2 if hit==len(g) and not bad else (1 if hit*2>=len(g) and not bad else 0)
    return s,hit,bad
def valid(out):
    return bool(out) and len(re.findall(r'[\u4e00-\u9fff]',out))<=80 and not re.search(r'[A-Za-z]{4,}',out)
if __name__=="__main__":
    path=sys.argv[1]; name=os.path.basename(path); nothink="Qwen3-" in name and "2507" not in name
    if path=="LITERAL":
        res=[dict(id=c[0],out=c[4],score=score(c[4],c)[0]) for c in C]
        json.dump(res,open("res_LITERAL.json" if os.environ.get("CASES")!="ext" else "ext_LITERAL.json","w"),ensure_ascii=False,indent=1);print(sum(r["score"] for r in res));sys.exit()
    t=time.time(); llm=Llama(path,n_ctx=2048,n_threads=8,verbose=False); load=time.time()-t
    res=[]
    for c in C:
        m=msgs(c,nothink); ntok=len(llm.tokenize(llm.metadata and "".join(x["content"] for x in m).encode()))
        t0=time.time(); first=None; toks=0; out=""
        for ch in llm.create_chat_completion(m,temperature=0,max_tokens=80,stream=True):
            d=ch["choices"][0]["delta"].get("content")
            if d:
                if first is None: first=time.time()
                toks+=1; out+=d
        end=time.time()
        out=re.sub(r"<think>.*?</think>","",out,flags=re.S).strip().split("\n")[0].strip().strip('"「」')
        s,hit,bad=score(out,c)
        res.append(dict(id=c[0],cat=c[1],src=c[3],out=out,score=s,valid=valid(out),ttft=round((first or end)-t0,3),gen_tps=round((toks-1)/max(end-first,1e-6),1) if first and toks>1 else None,prompt_tok_approx=ntok))
        print(c[0],s,out,res[-1]["ttft"],flush=True)
    sm=dict(model=name,size_mb=round(os.path.getsize(path)/1e6),load_s=round(load,2),score=sum(r["score"] for r in res),max=2*len(C),full=sum(r["score"]==2 for r in res),valid=sum(r["valid"] for r in res),ttft_med=sorted(r["ttft"] for r in res)[15],tps_med=sorted(r["gen_tps"] or 0 for r in res)[15])
    json.dump(dict(summary=sm,results=res),open(f"res_{name}.json" if os.environ.get("CASES")!="ext" else f"ext_{name}.json","w"),ensure_ascii=False,indent=1); print(sm)
