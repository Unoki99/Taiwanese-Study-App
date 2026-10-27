# Builds cards.json for 方方詞卡 from the shared 方方 data.json (the MOE-based build).
#   python3 build_cards.py data.json rime-essay/essay.txt FangfangCards/cards.json
import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anchor import parse, code_to_haolo, code_to_tl, code_to_poj, code_to_zhuyin

D = json.load(open(sys.argv[1]))
ESSAY = sys.argv[2]
SYLT = D["syl"]
PLACES = D["places"]

freq = {}
for line in open(ESSAY, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 2 and p[1].isdigit():
        freq[p[0]] = max(freq.get(p[0], 0), int(p[1]))

def syl(c, s, place=None):        # s: 0 皓羅, 1 台羅, 2 白話字, 3 方音
    if s == 3:
        z = SYLT[c][0]
        # with a place chosen, Tâi-lô o is ㄛ — except 臺南 and 高雄, where o is always said ㄜ
        return z.replace("ㄜ", "ㄛ") if place is not None and "ø" in c and not PLACES[place].startswith(("臺南", "高雄")) else z
    if s == 1: return D["tl"][c][0]
    if s == 2: return D["pj"][c]
    return SYLT[c][1]

def is_code(t): return t in SYLT

def render(tokens, s, place=None):
    out, prev = "", False
    for t in tokens:
        cap = t.startswith("^"); c = t[1:] if cap else t
        if is_code(c):
            if s != 3 and prev: out += "-"
            x = syl(c, s, place)
            if cap and s != 3: x = x[:1].upper() + x[1:]
            out += x; prev = True
        elif t == "--":
            if s != 3: out += "--"
            prev = False
        elif t == "_": out += " "; prev = False
        elif t.startswith("~"): out += t[1:]; prev = False
        else: out += t; prev = False
    return out

def tokens_for(k, codes):
    cs = codes.split()
    base = D["tok"].get(k)
    if not base: return cs
    i, out = 0, []
    for t in base.split():
        cap = t.startswith("^"); c = t[1:] if cap else t
        if is_code(c):
            out.append(("^" if cap else "") + (cs[i] if i < len(cs) else c)); i += 1
        else: out.append(t)
    return out

def forms(k, codes, place=None):
    tk = tokens_for(k, codes)
    return [render(tk, s, place) for s in range(3)], render(tk, 3, place)

TOK = re.compile(r"\{(\^?)([^}]+)\}")
def sent(tpl, s, blank=None):
    """romanize a sentence template; blank = (start, n) token range to replace with ＿＿"""
    toks = list(TOK.finditer(tpl))
    res, pos = "", 0
    for idx, m in enumerate(toks):
        res += tpl[pos:m.start()]
        cap, c = m.group(1), m.group(2)
        if blank and blank[0] <= idx < blank[0] + blank[1]:
            if idx == blank[0]: res += "＿＿"
            else: res = re.sub(r"[-‑]$", "", res)
        else:
            t = syl(c, s) if is_code(c) else c
            res += (t[:1].upper() + t[1:]) if cap else t
        pos = m.end()
    return res + tpl[pos:]

# topics worth a deck: skip stroke counts, "全部", train lines, counties
BAD_TOPIC = re.compile(r"畫|全部|線|捷運|輕軌|鐵路|機場|縣$|市$|其他$|海港|外交")
RANK = {"白": 0, "俗": 1, "": 2, "文": 3}
TYPE_LABEL = {1: "臺華共同", 3: "附錄"}

# Taiwanese frequency: in how many MOE example sentences does this word (same characters AND reading) appear?
EXS = []
for per in D["ex"].values():
    for lst in per:
        for eh, tpl, zh, name in lst:
            EXS.append((eh, [mm.group(2) for mm in TOK.finditer(tpl)]))
by_char = {}
for i, (eh, _) in enumerate(EXS):
    for ch in set(eh): by_char.setdefault(ch, []).append(i)
def tw_count(h, codes):
    n, L = 0, len(codes)
    for i in by_char.get(h[0], []):
        eh, tc = EXS[i]
        if h in eh and any(tc[j:j + L] == codes for j in range(len(tc) - L + 1)): n += 1
    return n

def link_list(keys):
    out = []
    for k in keys[:8]:
        h, c = k.split("\t")
        out.append([h, forms(k, c)[0][0] if c else ""])
    return out

topic_count = {}
cards, seen = [], set()
for h, c in D["words"]:
    k = h + "\t" + c
    di = D["defs"]["m"].get(k)
    if di is None or k in seen: continue
    seen.add(k)
    codes = [x for x in c.split() if is_code(x)]
    if not codes: continue
    lines = D["defs"]["t"][di].split("\n")
    pos = (D["pos"].get(k) or "").split("|")
    exs = D["ex"].get(k) or []
    sy, an = D["sy"].get(k, {}), D["an"].get(k, {})
    defs = []
    for i, line in enumerate(lines):
        m = re.match(r"^(\d+)\.\s*(.*)$", line)
        text = m.group(2) if m else line
        xs = []
        for eh, tpl, zh, name in (exs[i] if i < len(exs) else []):
            x = {"h": eh, "r": [sent(tpl, s) for s in range(3)], "z": zh, "n": name}
            tc = [mm.group(2) for mm in TOK.finditer(tpl)]
            L = len(codes)
            at = next((j for j in range(len(tc) - L + 1) if tc[j:j + L] == codes), None)
            if h in eh and at is not None:
                x["bh"] = eh.replace(h, "＿＿", 1)
                x["br"] = [sent(tpl, s, (at, L)) for s in range(3)]
            xs.append(x)
        dd = {"p": pos[i] if i < len(pos) else "", "t": text, "x": xs}
        if sy.get(str(i)): dd["sy"] = link_list(sy[str(i)])
        if an.get(str(i)): dd["an"] = link_list(an[str(i)])
        defs.append(dd)
    reg = D["reg"].get(k, "")
    r, z = forms(k, c)
    card = {"k": k, "h": h, "r": r, "z": z, "c": codes, "a": D["au"].get(k), "g": reg, "d": defs}
    # 方音 with a place chosen (Tâi-lô o shown as ㄛ)
    zo = forms(k, c, 0)[1]
    if zo != z: card["zo"] = zo
    # dialect readings
    v = {}
    for p_, dc in D["dia"].get(k, {}).items():
        rr, zz = forms(k, dc, int(p_))
        v[p_] = {"r": rr, "z": zz}
    if v: card["v"] = v
    # other readings: 又 / 俗 / 合 / "/"
    o = []
    for alt in D["alt"].get(k, []):
        ac, label = alt[0], alt[1]
        tk = alt[2].split() if len(alt) > 2 else ac.split()
        o.append({"l": label or "又", "r": [render(tk, s) for s in range(3)], "z": render(tk, 3)})
    if o: card["o"] = o
    if k in D["sub"]: card["s"] = 1
    if TYPE_LABEL.get(D["typ"].get(k)): card["t"] = TYPE_LABEL[D["typ"][k]]
    ws = [x for x in sy.get("e", []) if not any(x in sy[i] for i in sy if i != "e")]
    wa = [x for x in an.get("e", []) if not any(x in an[i] for i in an if i != "e")]
    if ws: card["sy"] = link_list(ws)
    if wa: card["an"] = link_list(wa)
    cats = [i for i in D["cat"].get(k, []) if not BAD_TOPIC.search(D["cats"][i])]
    if cats:
        card["cats"] = cats
        for i in cats: topic_count[i] = topic_count.get(i, 0) + 1
    card["_t"], card["_f"], card["_r"] = tw_count(h, codes), freq.get(h, 0), RANK.get(reg, 2)
    cards.append(card)

cards.sort(key=lambda e: (-e["_t"], -e["_f"], e["_r"]))
for e in cards: del e["_t"], e["_f"], e["_r"]

# every tone of the last syllables, for the tone practice (spelled by rule)
tone_syl = {}
for e in cards:
    last = e["c"][-1]
    p = parse(last)
    if not p: continue
    base = last[:-1]
    for t in (1, 2, 3, 4, 5, 7, 8):
        cc = base + str(t)
        if parse(cc) and cc not in tone_syl:
            try: tone_syl[cc] = [code_to_haolo(cc), code_to_tl(cc), code_to_poj(cc)]
            except Exception: pass
for e in cards:
    for x in e["c"]:
        if x not in tone_syl: tone_syl[x] = [syl(x, 0), syl(x, 1), syl(x, 2)]

topics = [[i, D["cats"][i], n] for i, n in sorted(topic_count.items(), key=lambda x: -x[1]) if n >= 8]
json.dump({"v": 2, "cards": cards, "syl": tone_syl, "places": PLACES, "topics": topics},
          open(sys.argv[3], "w"), ensure_ascii=False, separators=(",", ":"))
print(len(cards), "cards;", sum(1 for e in cards if e["a"] is not None), "with audio;",
      sum(1 for e in cards for d in e["d"] for x in d["x"] if "bh" in x), "blankable examples;",
      sum(1 for e in cards if "v" in e), "with dialect readings;", len(topics), "topics")
print("first 40:", " ".join(e["h"] for e in cards[:40]))
