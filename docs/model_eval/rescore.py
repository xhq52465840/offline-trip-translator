import json,glob,re
from cases import C
OK={c[0]:[k for grp in c[6] for k in grp if "万" in k] for c in C}
def strict(r):
    s=r["score"]
    ws=re.findall(r'(\d+(?:\.\d+)?)万',r["out"])
    if ws and OK.get(r["id"]):
        if any(f"{w}万" not in OK[r["id"]] for w in ws): s=0
    if not r.get("valid",True): s=min(s,1)
    return s
if __name__=="__main__":
    rows=[]
    for f in sorted(glob.glob("res_*.json")):
        d=json.load(open(f))
        if isinstance(d,list):
            rows.append(("LITERAL(模拟字面基线)","-",sum(x["score"] for x in d),"-","-","-","-")); continue
        sm=d["summary"]; st=sum(strict(r) for r in d["results"])
        for r in d["results"]: r["strict"]=strict(r)
        json.dump(d,open(f,"w"),ensure_ascii=False,indent=1)
        rows.append((sm["model"],sm["size_mb"],sm["score"],st,sm["valid"],sm["ttft_med"],sm["tps_med"]))
    print("|模型|文件MB|关键词分/60|严格分/60|格式合格/30|TTFT中位s|生成tok/s中位|")
    for r in sorted(rows,key=lambda x:-x[3] if x[3]!="-" else 0): print("|"+"|".join(map(str,r))+"|")
