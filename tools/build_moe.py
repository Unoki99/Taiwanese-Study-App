# Builds the shared 方方 dictionary data (data2.json) from the MOE 臺灣台語常用詞辭典 spreadsheet.
# Every reading is stored as "anchor" syllable codes; 方音 / 皓羅 / 台羅 / 白話字 come from anchor.py rules.
import json, re, sys, collections, unicodedata as U
from anchor import tl_split, tl_to_code, code_to_zhuyin, code_to_haolo, code_to_tl, code_to_poj, parse

S = json.load(open(sys.argv[1]))
OWN = json.load(open(sys.argv[2]))           # own.json: your own added words (自補), not from the dictionary
OUT = sys.argv[3]

PLACES = S["語音差異"][0][2:]                 # 10 places, in the file's order
G1 = {PLACES.index(p) for p in ("宜蘭偏漳腔", "臺南混合腔", "高雄混合腔", "臺中偏漳腔")}
TYPES = ["主詞目", "臺華共同詞", "單字不成詞者", "附錄", "近反義詞不單列詞目者", "自補"]

used_codes = set()
problems = collections.Counter()

# ------------------------------------------------------------------ readings
SYL = re.compile(r"[A-Za-z̀-ͯⁿ]+")

def reading(text):
    """Tâi-lô text -> list of tokens. Codes (with '^' if capitalised), '--' light tone,
    '_' space, other punctuation kept as literal tokens, '~xyz' for an unconvertible syllable."""
    t = U.normalize("NFD", text.replace("　", " ").strip())
    toks, pos = [], 0
    for m in SYL.finditer(t):
        sep = t[pos:m.start()]
        pos = m.end()
        toks += separators(sep, bool(toks))
        w, tone, cap = tl_split(m.group())
        c = tl_to_code(w, tone)
        if c is None:
            problems[w + str(tone)] += 1
            toks.append("~" + U.normalize("NFC", m.group()))
        else:
            used_codes.add(c)
            toks.append(("^" if cap else "") + c)
    toks += separators(t[pos:], True, tail=True)
    return toks

def separators(sep, inside, tail=False):
    out = []
    i = 0
    sep = U.normalize("NFC", sep)
    while i < len(sep):
        if sep.startswith("--", i): out.append("--"); i += 2
        elif sep[i] == "-": i += 1                       # ordinary hyphen = default join
        elif sep[i] == " ":
            if out and out[-1] == "_": pass
            else: out.append("_")
            i += 1
        else:
            out.append(sep[i]); i += 1
    if not inside: out = [x for x in out if x not in ("_",)]
    if tail: out = [x for x in out if x != "_"]
    return out

def rstr(toks): return " ".join(toks)
def codes_only(toks): return [t.lstrip("^") for t in toks if parse(t.lstrip("^"))]

def alternatives(raw):
    """'【白】peh/pueh' -> (register, [reading strings])"""
    reg = ""
    m = re.match(r"^【(白|文|俗)】", raw)
    if m: reg = m.group(1)
    raw = re.sub(r"【.*?】", "", raw)
    alts = [rstr(reading(a)) for a in raw.split("/") if a.strip()]
    return reg, alts

# ------------------------------------------------------------------ dialect rule for "/" readings
INI = re.compile(r"^(tsh|ts|ph|th|kh|ng|[pbmtnlkghsj]?)(.*)$")
CLEAN = {("enn", "inn"), ("e", "i"), ("inn", "i"), ("ueh", "uih")}    # (group-1 form, others' form)

def tl_syllables(rs):
    return [code_to_tl(t.lstrip("^")) for t in rs.split() if parse(t.lstrip("^"))]

def plain(s):
    w, tone, _ = tl_split(s)
    return w, tone

def style(main, alt):
    """'G1' if alt is the 宜蘭/臺南/高雄/臺中 form of main, 'G2' if the other way round, None if
    the two differ in anything else."""
    a, b = tl_syllables(main), tl_syllables(alt)
    if len(a) != len(b) or a == b: return None
    st = set()
    for x, y in zip(a, b):
        if x == y: continue
        (wx, tx), (wy, ty) = plain(x), plain(y)
        if tx != ty: return None
        (ix, rx), (iy, ry) = INI.match(wx).groups(), INI.match(wy).groups()
        if ix != iy: return None
        if (ry, rx) in CLEAN: st.add("G1")
        elif (rx, ry) in CLEAN: st.add("G2")
        else: return None
    return st.pop() if len(st) == 1 else None

# ------------------------------------------------------------------ entries
rows = [r + [""] * (6 - len(r)) for r in S["詞目"][1:]]
E, by_id = [], {}
cats = []; cat_ix = {}
for r in rows:
    eid, typ, han, rom, cat, audio = r[:6]
    sub = "【替】" in han
    h = re.sub(r"【.*?】", "", han).strip()
    e = {"i": int(eid), "h": h, "t": TYPES.index(typ)}
    if sub: e["s"] = 1
    if rom:
        reg, alts = alternatives(rom)
        e["r"] = alts[0]
        if reg: e["g"] = reg
        if len(alts) > 1: e["a"] = [[a, ""] for a in alts[1:]]
    cl = []
    for c in [c.strip() for c in cat.split(",") if c.strip()]:
        if c not in cat_ix: cat_ix[c] = len(cats); cats.append(c)
        cl.append(cat_ix[c])
    if cl: e["c"] = cl
    m = re.match(r"^(\d+)\(1\)$", audio)
    if m: e["au"] = int(m.group(1))
    E.append(e); by_id[eid] = e

# 又唸作 / 俗唸作 / 合音唸作
for sheet, label in (("又唸作", "又"), ("俗唸作", "俗"), ("合音唸作", "合")):
    for r in S[sheet][1:]:
        if len(r) < 3 or r[0] not in by_id: continue
        e = by_id[r[0]]
        for a in r[2].split("/"):
            if a.strip():
                e.setdefault("a", []).append([rstr(reading(a)), label])

# dialects: 1. the readings the file gives per place
for r in S["語音差異"][1:]:
    if r[0] not in by_id: continue
    e = by_id[r[0]]
    for i, cell in enumerate(r[2:]):
        if not cell.strip(): continue
        forms = [rstr(reading(x)) for x in cell.split(",") if x.strip()]
        first = forms[0]
        if first != e.get("r"):
            e.setdefault("d", {})[str(i)] = first
        if len(forms) > 1:                                     # the place says it more than one way
            e.setdefault("dd", {})[str(i)] = forms[1:]
explicit = {(e["i"], k) for e in E for k in e.get("d", {})}     # readings the file states
for e in E:
    if e.get("d"): e["dx"] = sorted(e["d"], key=int)          # remembered, so the apps can tell stated from guessed

# 詞彙比較 also tells how a word is said in each place, sometimes in two ways (粗紙 in 高雄:
# tshoo-tsuá and thoo-tsuá). Where its word is a dictionary entry (same characters, same number of
# syllables, closest reading), those readings are stated local readings too.
by_han = collections.defaultdict(list)
for e in E:
    if "r" in e: by_han[e["h"]].append(e)
said = collections.OrderedDict()                     # (han, place index) -> [readings]
for r in S["詞彙比較"][1:]:
    if len(r) < 5 or r[2] not in PLACES or not r[4].strip(): continue
    k = (r[3], str(PLACES.index(r[2])))
    rs = rstr(reading(r[4]))
    if rs not in said.setdefault(k, []): said[k].append(rs)
# which dictionary entry a 詞彙比較 word is: same characters and number of syllables; if several, the one
# closest to the readings given for all the places together (做伙: 宜蘭 tsò-hué is exactly the main reading)
all_forms = collections.defaultdict(list)
for (han, pl), forms in said.items(): all_forms[han] += [codes_only(f.split()) for f in forms]
def entry_for(han, n):
    cands = [e for e in by_han.get(han, []) if len(codes_only(e["r"].split())) == n]
    if len(cands) <= 1: return cands[0] if cands else None
    def overlap(e):
        m = codes_only(e["r"].split())
        return sum(sum(a == b for a, b in zip(m, f)) for f in all_forms[han] if len(f) == n)
    best = max(overlap(e) for e in cands)
    top = [e for e in cands if overlap(e) == best]
    return top[0] if len(top) == 1 else None
vocab_set = vocab_extra = 0
for (han, pl), forms in said.items():
    fc = [codes_only(f.split()) for f in forms]
    e = entry_for(han, len(fc[0]))
    if e is None: continue
    main = codes_only(e["r"].split())
    stated = []
    if (e["i"], pl) in explicit:                     # 語音差異 first, then what 詞彙比較 adds
        stated = [e["d"][pl]] + e.get("dd", {}).get(pl, [])
    elif "dd" in e and pl in e["dd"]:
        stated = [e["r"]] + e["dd"][pl]
    for f in forms:
        if codes_only(f.split()) not in [codes_only(x.split()) for x in stated]: stated.append(f)
    if not stated: continue
    if (e["i"], pl) not in explicit:
        if codes_only(stated[0].split()) == main: e.get("d", {}).pop(pl, None)   # the place says it like 通行
        else: e.setdefault("d", {})[pl] = stated[0]
        e.setdefault("dx", [])
        if pl not in e["dx"]: e["dx"].append(pl); vocab_set += 1
    extra = [x for x in stated[1:] if codes_only(x.split()) != codes_only(stated[0].split())]
    if extra:
        e.setdefault("dd", {})[pl] = extra; vocab_extra += 1
print("詞彙比較 readings used:", vocab_set, "places with a second reading:", vocab_extra)
explicit |= {(e["i"], p) for e in E for p in e.get("dx", [])}

# dialects: 2. a character's local reading (as MOE states it in 語音差異) carries into words, but only where
#    the word uses that same reading of the character (same 台羅 spelling): 十全 tsa̍p-tsn̂g follows 全 tsn̂g,
#    while 十全 si̍p-tsuân (the literary reading) stays as it is. A character's own "/" spellings lead to the
#    same local reading (過 kuè/kè → 鹿港 kèr).
R_ADD = {"ø": "ɵ", "e": "ə", "i": "ɨ"}
rrule = collections.defaultdict(dict)            # (character, code) -> {place: code}
for e in E:
    if len(e["h"]) != 1 or "r" not in e or "d" not in e: continue
    m = e["r"].split()
    if len(m) != 1: continue
    for pl, r in e["d"].items():
        if (e["i"], pl) not in explicit: continue
        n = r.split()
        if len(n) == 1 and n[0] != m[0]:
            rrule[(e["h"], m[0])][pl] = n[0]
            for alt, label in e.get("a", []):
                al = alt.split()
                if label == "" and len(al) == 1 and al[0] != n[0] and (e["h"], al[0]) not in rrule:
                    rrule[(e["h"], al[0])][pl] = n[0]

# words (2+ characters) whose local reading MOE gives: (characters, codes) -> {place: [codes]}
wrule = collections.defaultdict(dict)
for e in E:
    if "r" not in e or len(e["h"]) < 2: continue
    m = codes_only(e["r"].split())
    if len(m) != len(e["h"]): continue
    for pl in e.get("dx", []):
        if (e["i"], pl) not in explicit: continue
        n = codes_only(e.get("d", {}).get(pl, e["r"]).split())
        if len(n) == len(m): wrule[(e["h"], " ".join(m))][pl] = n

# dialects: 3. for each place without MOE's own reading of the word, syllable by syllable:
#    a. the local reading of a word inside it that MOE gives for the place, else the character's local
#       reading (rule 2), else
#    b. the syllable from MOE's "/" form for that place: the form that agrees with the local readings of
#       the other syllables (按呢生 án-ne-senn / án-ní-sinn: 生 → sinn, so 呢 → ní), or else the
#       enn/inn, e/i, inn/i, ueh/uih pair rule between the "/" forms
#       (宜蘭, 臺南, 高雄, 臺中 enn/e/inn/ueh; the other places inn/i/i/uih), else
#    c. the 通行 syllable
carried = from_slash = 0
for e in E:
    if "r" not in e: continue
    toks = e["r"].split()
    code_pos = [i for i, t in enumerate(toks) if parse(t.lstrip("^"))]
    chars = list(e["h"])
    main = [toks[i].lstrip("^") for i in code_pos]
    slash = [a for a, label in e.get("a", []) if label == ""]
    slash = [a for a in slash if len(codes_only(a.split())) == len(main)]
    for pl in map(str, range(len(PLACES))):
        if (e["i"], pl) in explicit: continue
        local = {}                                   # syllable position -> local reading (rule a)
        if len(main) == len(chars) and len(chars) > 1:
            # a word inside this word that MOE gives for the place (鬥做伙 contains 做伙: 鹿港 tsuè-hér),
            # longest first
            for L in range(len(chars) - 1, 1, -1):
                for st in range(0, len(chars) - L + 1):
                    if any(n in local for n in range(st, st + L)): continue
                    w = wrule.get(("".join(chars[st:st + L]), " ".join(main[st:st + L])), {}).get(pl)
                    if w and len(w) == L:
                        for j in range(L): local[st + j] = w[j]
            for n, (ch, c) in enumerate(zip(chars, main)):
                if n in local: continue
                new = rrule.get((ch, c), {}).get(pl)
                if new: local[n] = new
        # which "/" form fills the other syllables (rule b)
        form = None
        if slash:
            def hits(f):
                fc = codes_only(f.split())
                return sum(1 for n, v in local.items() if fc[n] == v or rrule.get((chars[n], fc[n]), {}).get(pl) == v) \
                    if len(chars) == len(fc) else 0
            best = max(slash, key=hits)
            if local and hits(best) > 0 and any(codes_only(best.split())[n] != main[n] for n in range(len(main)) if n not in local):
                form = best
            if form is None:
                for a in slash:
                    st = style(e["r"], a)
                    if st and (st == "G1") == (int(pl) in G1): form = a; break
        base = (form or e["r"]).split()
        fpos = [i for i, t in enumerate(base) if parse(t.lstrip("^"))]
        if len(fpos) == len(chars) and len(chars) > 1:
            for n, (ch, i) in enumerate(zip(chars, fpos)):
                c = base[i].lstrip("^")
                new = local.get(n) if c == main[n] else rrule.get((ch, c), {}).get(pl)
                if new: base[i] = ("^" if base[i].startswith("^") else "") + new
        if codes_only(base) == main: continue
        e.setdefault("d", {})[pl] = " ".join(base)
        if form: from_slash += 1
        else: carried += 1

print("rules", len(rrule), "local readings carried into words", carried, "using a / form", from_slash)

# senses, examples
sense_entry, sense_ord = {}, {}
for r in S["義項"][1:]:
    eid, sid, pos, text = (r + [""] * 4)[:4]
    if eid not in by_id: continue
    e = by_id[eid]
    e.setdefault("m", []).append({"p": pos, "t": text})
    sense_entry[sid] = eid
    sense_ord[sid] = len(e["m"]) - 1

TOK = SYL
def template(text):
    t = U.normalize("NFD", text)
    out, pos = [], 0
    for m in TOK.finditer(t):
        out.append(U.normalize("NFC", t[pos:m.start()]))
        pos = m.end()
        w, tone, cap = tl_split(m.group())
        c = tl_to_code(w, tone)
        if c is None:
            problems[w + str(tone)] += 1
            out.append(U.normalize("NFC", m.group()))
        else:
            used_codes.add(c)
            out.append("{" + ("^" if cap else "") + c + "}")
    out.append(U.normalize("NFC", t[pos:]))
    return "".join(out)

for r in S["例句"][1:]:
    eid, sid, n, han, rom, zh, name = (r + [""] * 7)[:7]
    if sid not in sense_entry: continue
    e = by_id[sense_entry[sid]]
    e["m"][sense_ord[sid]].setdefault("x", []).append([han, template(rom), zh, name])

# synonyms / antonyms
def add(e, key, target, own=None):
    if target == own: return
    lst = e.setdefault(key, [])
    if target not in lst: lst.append(target)
for sheet, key in (("義項tuì義項近義", "sy"), ("義項tuì義項反義", "an")):
    for r in S[sheet][1:]:
        if r[0] in sense_entry and r[3] in sense_entry:
            e = by_id[sense_entry[r[0]]]
            add(e["m"][sense_ord[r[0]]], key, int(sense_entry[r[3]]), e["i"])
for sheet, key in (("義項tuì詞目近義", "sy"), ("義項tuì詞目反義", "an")):
    for r in S[sheet][1:]:
        if r[0] in sense_entry and r[3] in by_id:
            e = by_id[sense_entry[r[0]]]
            add(e["m"][sense_ord[r[0]]], key, int(r[3]), e["i"])
for sheet, key in (("詞目tuì詞目近義", "sy"), ("詞目tuì詞目反義", "an")):
    for r in S[sheet][1:]:
        if r[0] in by_id and r[2] in by_id:
            add(by_id[r[0]], key, int(r[2]), by_id[r[0]]["i"])

# variant characters
for r in S["異用字"][1:]:
    if len(r) >= 3 and r[0] in by_id and r[2].strip():
        by_id[r[0]].setdefault("v", []).append(r[2].strip())

# your own added words (自補), unless the dictionary already has them
have = {(e["h"], " ".join(codes_only(e.get("r", "").split()))) for e in E}
own_id = 900000
for k in OWN.get("own", []):
    h, c = k.split("\t")
    if (h, c) in have: continue
    own_id += 1
    e = {"i": own_id, "h": h, "t": 5, "r": c}
    if OWN.get("defs", {}).get(k):
        e["m"] = [{"p": "", "t": t} for t in OWN["defs"][k]]
    for x in c.split(): used_codes.add(x)
    E.append(e)

# 詞彙比較: Mandarin word -> what each place says
cmp = collections.OrderedDict()
for r in S["詞彙比較"][1:]:
    if len(r) < 5: continue
    _, zh, place, han, rom = r[:5]
    if place not in PLACES: continue
    item = [PLACES.index(place), han, rstr(reading(rom))]
    cmp.setdefault(zh, [])
    if item not in cmp[zh]: cmp[zh].append(item)


# 名 / 姓: readings of characters in names
def name_sheet(sheet):
    out = collections.defaultdict(list)
    for r in S[sheet][1:]:
        r = r + [""] * 4
        han, rom, order, typ = r[:4]
        if not han or not rom: continue
        out[han].append([rstr(reading(rom)), typ])
    return out
names, surnames = name_sheet("名"), name_sheet("姓")

# ------------------------------------------------------------------ syllable table
syl = {}
for c in sorted(used_codes):
    if not parse(c): continue
    syl[c] = [code_to_zhuyin(c), code_to_haolo(c), code_to_tl(c), code_to_poj(c)]

data = {"v": 2, "places": PLACES, "g1": sorted(G1), "types": TYPES, "cats": cats, "syl": syl,
        "E": E, "cmp": [[k, v] for k, v in cmp.items()], "names": names, "sur": surnames}
json.dump(data, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))

print("entries", len(E), {TYPES[t]: n for t, n in collections.Counter(e["t"] for e in E).items()})
print("with reading", sum(1 for e in E if "r" in e), "alternatives", sum(len(e.get("a", [])) for e in E))
print("dialect overrides: entries", sum(1 for e in E if "d" in e),
      "by place", {PLACES[int(k)]: n for k, n in collections.Counter(k for e in E for k in e.get("d", {})).items()})
print("senses", sum(len(e.get("m", [])) for e in E), "examples", sum(len(m.get("x", [])) for e in E for m in e.get("m", [])))
print("syn", sum(len(m.get("sy", [])) for e in E for m in e.get("m", [])) + sum(len(e.get("sy", [])) for e in E),
      "ant", sum(len(m.get("an", [])) for e in E for m in e.get("m", [])) + sum(len(e.get("an", [])) for e in E))
print("variants", sum(len(e.get("v", [])) for e in E), "cmp concepts", len(cmp), "names", len(names), "surnames", len(surnames))
print("syllables", len(syl), "unconvertible", sum(problems.values()), problems.most_common(10))
