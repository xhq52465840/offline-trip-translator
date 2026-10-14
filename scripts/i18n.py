#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""界面国际化（三语改造 P7）。唯一来源：i18n/strings.json（中文原文 → 英文）。
  python3 scripts/i18n.py keys    列出代码里用到、但 strings.json 缺英文的键
  python3 scripts/i18n.py gen     生成 Localizable.xcstrings、L10nTable.swift、InfoPlist.strings
  python3 scripts/i18n.py check   完整性检查：每个键都有英文；生成文件最新；视图里没有带插值的中文字面量；
                                  TripAppModel 里中文字面量只出现在 L10n.t/f 里或标了 // i18n-ok 的行
"""
import json, os, re, sys, glob
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
J = os.path.join(ROOT, "i18n", "strings.json")
APP = os.path.join(ROOT, "App", "TripApp")
MODEL = os.path.join(ROOT, "TripCore", "Sources", "TripAppModel")
XC = os.path.join(APP, "Localizable.xcstrings")
TABLE = os.path.join(MODEL, "L10nTable.swift")
INFO_EN = os.path.join(APP, "en.lproj", "InfoPlist.strings")
INFO_ZH = os.path.join(APP, "zh-Hans.lproj", "InfoPlist.strings")
HAN = re.compile(r"[\u4e00-\u9fff]")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
L10N = re.compile(r'L10n\.[tf]\(\s*"((?:[^"\\\n]|\\.)*)"')
MODEL_ALLOW_FILES = {"Scenario.swift", "UITestMode.swift", "L10nTable.swift"}
VIEW_SKIP_FILES = {"Previews.swift"}

def code_lines(path):
    in_block = False
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        t = line.strip()
        if t.startswith("/*"): in_block = True
        if in_block:
            if "*/" in t: in_block = False
            continue
        if t.startswith("//"): continue
        out, q = "", False
        for k, ch in enumerate(line):
            if ch == '"' and (k == 0 or line[k - 1] != "\\"): q = not q
            if not q and line[k:k + 2] == "//": break
            out += ch
        yield i, out, line

def scan():
    keys, view_keys, problems = set(), set(), []
    for f in sorted(glob.glob(os.path.join(MODEL, "*.swift")) + glob.glob(os.path.join(APP, "*.swift"))):
        name = os.path.basename(f); is_view = f.startswith(APP)
        if name in VIEW_SKIP_FILES: continue
        for i, code, raw in code_lines(f):
            for m in L10N.finditer(code): keys.add(m.group(1))
            if "#Preview" in code: continue
            for m in LIT.finditer(L10N.sub("", code)):
                s = m.group(1)
                if not HAN.search(s): continue
                if is_view:
                    if "LangNames" in raw or "i18n-ok" in raw: continue
                    if "\\(" in s: problems.append(f"{name}:{i} 视图里带插值的中文字面量，改用 L10n.f：{s[:40]}")
                    else: view_keys.add(s)
                else:
                    if name in MODEL_ALLOW_FILES or "i18n-ok" in raw: continue
                    problems.append(f"{name}:{i} 模型层中文字面量未经 L10n：{s[:40]}")
    return keys, view_keys, problems

def load(): return json.load(open(J, encoding="utf-8")) if os.path.exists(J) else {}

def unesc(s): return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")

def gen_files(tab, keys, view_keys):
    xc = {"sourceLanguage": "zh-Hans", "version": "1.0", "strings": {}}
    for k in sorted(set(view_keys) | set(keys)):
        xc["strings"][unesc(k)] = {"extractionState": "manual", "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": unesc(str(tab.get(k, "")))}}}}
    xcs = json.dumps(xc, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    rows = "\n".join(f'        "{k}": "{tab[k]}",' for k in sorted(keys) if k in tab)
    swift = ("// 自动生成：python3 scripts/i18n.py gen（来源 i18n/strings.json）。不要手改。\n"
             "public enum L10nTable {\n    public static let en: [String: String] = [\n" + rows + "\n    ]\n}\n")
    info = tab.get("__InfoPlist__", {})
    return {XC: xcs, TABLE: swift,
            INFO_EN: "".join(f'"{k}" = "{v["en"]}";\n' for k, v in sorted(info.items())),
            INFO_ZH: "".join(f'"{k}" = "{v["zh"]}";\n' for k, v in sorted(info.items()))}

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    tab = load(); keys, view_keys, problems = scan(); allk = keys | view_keys
    missing = sorted(k for k in allk if not str(tab.get(k, "")).strip())
    if cmd == "keys":
        for k in missing: print(json.dumps(k, ensure_ascii=False))
        for p in problems: print("#", p)
        return
    files = gen_files(tab, keys, view_keys)
    if cmd == "gen":
        for p, c in files.items():
            os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w", encoding="utf-8").write(c)
        print(f"generated {len(allk)} keys ({len(keys)} model, {len(view_keys)} view)"); return
    ok = True
    for k in missing: print("缺英文：", k); ok = False
    for p in problems: print(p); ok = False
    for p, c in files.items():
        if not os.path.exists(p) or open(p, encoding="utf-8").read() != c: print("生成文件过期：", os.path.relpath(p, ROOT)); ok = False
    for k in sorted(k for k in tab if k not in allk and not k.startswith("__")): print("（提示）未使用的键：", k)
    for k in allk:
        v = str(tab.get(k, ""))
        if HAN.search(v): print("英文里有汉字：", k); ok = False
        if k.count("%@") != v.count("%@"): print("格式符数量不一致：", k); ok = False
    print(f"i18n check: {'OK' if ok else 'FAILED'} · {len(allk)} keys ({len(keys)} model, {len(view_keys)} view)")
    sys.exit(0 if ok else 1)

if __name__ == "__main__": main()
