# 评分单测（不加载模型）：python scripts/test_eval_public.py
import os, sys; sys.path.insert(0, os.path.dirname(__file__))
from eval_public import chrfpp, summarize, clean
assert chrfpp(["已经到了吗？"], ["已经到了吗？"], zh=True) == 100.0
assert chrfpp(["how much is it"], ["how much is it"]) == 100.0
assert chrfpp(["完全不同"], ["已经到了吗？"], zh=True) < 20
good = chrfpp(["How much does this cost?"], ["How much does this cost?"]); part = chrfpp(["How much is this?"], ["How much does this cost?"])
assert good > part > 0
rows = [{"task": "mt_id_zh", "source_dataset": "Tatoeba", "hyp": "她家在哪儿？", "ref": "她家在哪儿？"},
        {"task": "mt_id_en", "source_dataset": "Wikivoyage Indonesian phrasebook", "hyp": "Please clean the table.", "ref": "Please clean the table."}]
s = summarize(rows); assert s["task:mt_id_zh"]["chrf"] == 100.0 and s["source:Wikivoyage Indonesian phrasebook/mt_id_en"]["n"] == 1
assert clean('「你好」\n多余') == "你好"
print("ok")
