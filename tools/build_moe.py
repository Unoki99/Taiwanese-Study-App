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

# dialects: 2. enn/inn, e/i, inn/i, ueh/uih between the "/" readings
for e in E:
    if "r" not in e or "a" not in e: continue
    for alt, label in e["a"]:
        if label: continue
        st = style(e["r"], alt)
        if not st: continue
        for i in range(len(PLACES)):
            if str(i) in e.get("d", {}): continue          # the file's own reading wins
            if (st == "G1") == (i in G1):
                e.setdefault("d", {})[str(i)] = alt

# dialects: 3. a character's local reading (as MOE states it in 語音差異) carries into compounds,
#    but only where the compound uses that same reading of the character (same 台羅 spelling),
#    so 十全 tsa̍p-tsn̂g follows 全 tsn̂g, while 十全 si̍p-tsuân (the literary reading) stays as it is
R_ADD = {"ø": "ɵ", "e": "ə", "i": "ɨ"}
def only_r(main, new):
    pm, pn = parse(main), parse(new)
    if not pm or not pn: return False
    if (pm[0], pm[1], pm[3], pm[4]) != (pn[0], pn[1], pn[3], pn[4]): return False
    a, b = pm[2], pn[2]
    return len(a) == len(b) and sum(x != y for x, y in zip(a, b)) == 1 and \
        all(x == y or R_ADD.get(x) == y for x, y in zip(a, b))
rrule = collections.defaultdict(dict)            # (character, code) -> {place: code}
for e in E:
    if len(e["h"]) != 1 or "r" not in e or "d" not in e: continue
    m = e["r"].split()
    if len(m) != 1: continue
    for pl, r in e["d"].items():
        if (e["i"], pl) not in explicit: continue
        n = r.split()
        if len(n) == 1 and n[0] != m[0]:          # any local difference of this reading (matched by reading, so
                                                 # a literary reading with its own spelling is never touched)
            rrule[(e["h"], m[0])][pl] = n[0]
carried = 0
for e in E:
    if "r" not in e or len(e["h"]) < 2: continue
    toks = e["r"].split()
    code_pos = [i for i, t in enumerate(toks) if parse(t.lstrip("^"))]
    chars = list(e["h"])
    if len(code_pos) != len(chars): continue
    for pl in map(str, range(len(PLACES))):
        if (e["i"], pl) in explicit: continue
        base = e.get("d", {}).get(pl, e["r"]).split()
        if len(base) != len(toks): continue
        changed = False
        for ch, i in zip(chars, code_pos):
            c = toks[i].lstrip("^")
            new = rrule.get((ch, c), {}).get(pl)
            if new:
                base[i] = ("^" if toks[i].startswith("^") else "") + new
                changed = True
        if changed:
            e.setdefault("d", {})[pl] = " ".join(base)
            carried += 1
print("rules", len(rrule), "dialect readings carried into compounds", carried)

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
vocab_set = vocab_extra = 0
for (han, pl), forms in said.items():
    fc = [codes_only(f.split()) for f in forms]
    cands = [e for e in by_han.get(han, []) if len(codes_only(e["r"].split())) == len(fc[0])]
    if not cands: continue
    def overlap(e):
        m = codes_only(e["r"].split())
        return max(sum(a == b for a, b in zip(m, f)) for f in fc)
    best = max(overlap(e) for e in cands)
    top = [e for e in cands if overlap(e) == best]
    if len(top) != 1 or best == 0: continue
    e = top[0]
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
