# -*- coding: utf-8 -*-
"""从公开数据集构建「公开来源」评测集（不含任何自写句子）。原始文件由 fetch.sh 下载到 raw/（不进仓库）。
产出 public_eval.jsonl：每行 {id, source_dataset, license, scene, src_id, src_lang, ref_zh?, ref_en?, ref_id_formal?, task}
task: mt_id_zh（有中文参考）| mt_id_en（英文参考，枢轴）| slang_norm（非正式→正式印尼语）| lexicon（俚语词→正式词）
"""
import csv, json, re, sys, os, random
R = "raw"; rnd = random.Random(0)
SCENE_KW = {
 "ride": r"\b(taksi|taxi|grab|gojek|ojek|ojol|sopir|supir|driver|antar|jemput|turun|berhenti)\b",
 "hotel": r"\b(hotel|kamar|penginapan|kunci|handuk|check.?in|check.?out|resepsionis)\b",
 "restaurant": r"\b(makan|minum|pedas|menu|nasi|restoran|warung|lapar|haus|kopi|teh|pesan)\b",
 "shopping": r"\b(harga|harganya|murah|mahal|beli|jual|toko|pasar|diskon|kurang)\b",
 "money": r"\b(uang|bayar|rupiah|ribu|juta|rb|jt|atm|kembalian|tukar)\b",
 "directions": r"\b(di mana|dimana|jalan|kiri|kanan|lurus|stasiun|bandara|dekat|jauh|peta)\b",
 "health": r"\b(sakit|dokter|obat|apotek|rumah sakit|demam|alergi)\b",
 "emergency": r"\b(polisi|tolong|hilang|copet|maling|darurat)\b",
 "time": r"\b(jam|menit|besok|kemarin|nanti|sekarang)\b",
}
def scene(s):
    s = s.lower()
    for k, p in SCENE_KW.items():
        if re.search(p, s): return k
    return None

# 训练集原文（去重用）
train_src = set()
for f in ["../out/train.jsonl", "../out/valid.jsonl", "../out/test.jsonl"]:
    for l in open(f, encoding="utf-8"):
        u = json.loads(l)["messages"][-2]["content"]
        m = re.search(r"对方原文：(.*)", u)
        if m: train_src.add(m.group(1).strip().lower())
def tok(s): return set(re.findall(r"[a-z0-9]+", s.lower()))
TT = [tok(s) for s in train_src]
def in_train(s):
    t = tok(s); return any(len(t & x) / max(1, len(t | x)) >= 0.6 for x in TT)

out = []
def add(**kw):
    if in_train(kw["src"]): return
    out.append(kw)

# 1) Tatoeba ind↔cmn（CC BY 2.0 FR）
ind = {}; cmn = {}
for l in open(f"{R}/ind_sentences.tsv", encoding="utf-8"):
    i, _, t = l.rstrip("\n").split("\t", 2); ind[i] = t
for l in open(f"{R}/cmn_sentences.tsv", encoding="utf-8"):
    i, _, t = l.rstrip("\n").split("\t", 2); cmn[i] = t
try:
    import opencc; t2s = opencc.OpenCC("t2s").convert
except Exception: t2s = lambda x: x
pairs = {}
for l in open(f"{R}/ind-cmn_links.tsv", encoding="utf-8"):
    a, b = l.split()[:2]
    if a in ind and b in cmn and a not in pairs: pairs[a] = cmn[b]
for i, zh in pairs.items():
    sc = scene(ind[i])
    if sc: add(source_dataset="Tatoeba", license="CC BY 2.0 FR", scene=sc, src_id=f"tatoeba:{i}", src=ind[i], ref_zh=t2s(zh), task="mt_id_zh")

# 2) FLORES-200 devtest（CC BY-SA 4.0）：正式书面语，按关键词选旅行相关句
fi = open(f"{R}/flores200_dataset/devtest/ind_Latn.devtest", encoding="utf-8").read().splitlines()
fz = open(f"{R}/flores200_dataset/devtest/zho_Hans.devtest", encoding="utf-8").read().splitlines()
fl = [(k, a, b) for k, (a, b) in enumerate(zip(fi, fz)) if scene(a) in ("ride", "hotel", "restaurant", "shopping", "money", "directions", "health")]
for k, a, b in rnd.sample(fl, min(60, len(fl))):
    add(source_dataset="FLORES-200 devtest", license="CC BY-SA 4.0", scene=scene(a), src_id=f"flores:devtest:{k}", src=a, ref_zh=b, task="mt_id_zh")

# 3) Wikivoyage 印尼语会话手册（CC BY-SA 4.0）：英→印短语，旅行场景章节
sec = None; WV_SCENE = {"Taxis and ride-sharing": "ride", "Lodging": "hotel", "Money": "money", "Eating": "restaurant", "Shopping": "shopping",
                        "Directions": "directions", "Problems": "emergency", "At the doctor's": "health", "Bus and train": "ride", "Bars": "restaurant",
                        "Authority": "emergency", "Basics": "chat"}
for l in open(f"{R}/wikivoyage_indonesian_phrasebook.wiki", encoding="utf-8"):
    m = re.match(r"^=+\s*(.+?)\s*=+\s*$", l)
    if m: sec = m.group(1); continue
    m = re.match(r"^; (.+?) : (.+?)(?: \(''.*)?$", l.strip())
    if m and sec in WV_SCENE:
        en = re.sub(r"''|\[\[|\]\]", "", m.group(1)).strip(); idn = re.sub(r"''|<br>.*", "", m.group(2)).strip()
        if 2 <= len(idn.split()) <= 14 and "&" not in idn and "|" not in idn and "_" not in idn and "..." not in idn and "..." not in en:
            add(source_dataset="Wikivoyage Indonesian phrasebook", license="CC BY-SA 4.0", scene=WV_SCENE[sec], src_id=f"wikivoyage:{sec}", src=idn, ref_en=en, task="mt_id_en")

# 4) STIF-Indonesia（MIT）：真实口语推文 → 正式印尼语（考俚语缩写理解）
inf = open(f"{R}/stif_test.inf", encoding="utf-8").read().splitlines(); frm = open(f"{R}/stif_test.for", encoding="utf-8").read().splitlines()
for k, (a, b) in enumerate(zip(inf, frm)):
    if len(a.split()) <= 25 and "xxx" not in a:
        add(source_dataset="STIF-Indonesia test", license="MIT", scene=scene(a) or "chat", src_id=f"stif:test:{k}", src=a, ref_id_formal=b, task="slang_norm")

for k, x in enumerate(out): x["id"] = f"P{k+1:04d}"
with open("public_eval.jsonl", "w", encoding="utf-8") as f:
    for x in out: f.write(json.dumps(x, ensure_ascii=False) + "\n")

# 5) 俚语词表覆盖：我们自写用例里的缩写在公开词表（Colloquial Indonesian Lexicon，无许可证声明 → 只引用、不再分发）中的对照
ours = ["udh", "sdh", "udah", "blm", "gk", "ga", "gak", "nggak", "brp", "sy", "lg", "mnt", "aja", "bgt", "makasih", "mksh", "lok", "bs", "yg", "dgn",
        "bntr", "jln", "dl", "kalo", "klo", "sampe", "gmn", "otw", "gpp", "rb", "jt", "tggu", "dong", "kak", "ongkir", "cod"]
lex = {}
if os.path.exists(f"{R}/colloquial-indonesian-lexicon.csv"):
    for r in csv.DictReader(open(f"{R}/colloquial-indonesian-lexicon.csv", encoding="utf-8")):
        lex.setdefault(r["slang"].strip().lower(), set()).add(r["formal"].strip().lower())
stif_tok = set(w for s in inf for w in s.lower().split())
cov = {w: {"lexicon_formal": sorted(lex.get(w, []))[:5], "in_STIF_test": w in stif_tok} for w in ours}
json.dump(cov, open("slang_coverage.json", "w"), ensure_ascii=False, indent=1)
from collections import Counter
print(len(out), Counter(x["source_dataset"] for x in out), Counter(x["task"] for x in out))
print("slang covered by lexicon:", sum(1 for v in cov.values() if v["lexicon_formal"]), "/", len(cov), "; in STIF:", sum(v["in_STIF_test"] for v in cov.values()))

# 6) 自写 60 条评测用例中，哪些俚语/缩写有公开来源佐证
sys.path.insert(0, "../../docs/model_eval")
from cases import C; from cases_ext import C2
back = []
for c in C + C2:
    ws = [w for w in re.findall(r"[a-z]+", c[3].lower()) if w in lex or w in stif_tok]
    slangish = [w for w in ws if w in lex and w not in lex[w]]
    back.append({"case": c[0], "src": c[3], "public_slang": sorted(set(slangish))})
json.dump(back, open("selfwritten_backing.json", "w"), ensure_ascii=False, indent=1)
print("self-written cases with >=1 slang token found in public lexicon:", sum(1 for b in back if b["public_slang"]), "/", len(back))
