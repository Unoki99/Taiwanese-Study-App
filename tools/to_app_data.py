# data2.json (full MOE build) -> data.json used by the converter website, the Safari extension and 方方詞卡.
# Keeps the old field layout (words, syl, tl, pj, defs, pos, ex, reg, own, au, gl, freq) so existing code keeps
# working, and adds the new information (dialects, alternatives, synonyms, topics, variants, ...).
import json, sys, re, collections, math
from anchor import parse, code_to_zhuyin, code_to_haolo, code_to_tl, code_to_poj

D = json.load(open(sys.argv[1]))
ESSAY = sys.argv[2]                          # rime-essay essay.txt (how common each character is)
OUT = sys.argv[3]

def codes_only(rs):
    out = []
    for t in rs.split():
        c = t.lstrip("^")
        if parse(c): out.append(c)
        elif t.startswith("~"): return None        # contains a syllable we can't spell
    return " ".join(out)

def needs_tokens(rs):
    return any(not parse(t) for t in rs.split())   # ^ capitals, -- light tone, spaces, punctuation

# entries with the same characters and reading (e.g. a word and the same word as a surname or place name)
# become one entry: meanings, topics and readings are merged
groups = collections.OrderedDict()
for e in D["E"]:
    c = codes_only(e["r"]) if "r" in e else None
    k = e["h"] + "\t" + c if c else None
    if k is None: continue
    groups.setdefault(k, []).append(e)
merged_into = {}
for k, es in groups.items():
    base = es[0]
    for o in es[1:]:
        merged_into[o["i"]] = base["i"]
        if o.get("m"): base.setdefault("m", []).extend(o["m"])
        for c in o.get("c", []):
            if c not in base.setdefault("c", []): base["c"].append(c)
        if o["r"] != base["r"]: base.setdefault("a", []).append([o["r"], ""])
        for a in o.get("a", []): base.setdefault("a", []).append(a)
        for p_, r in o.get("d", {}).items(): base.setdefault("d", {}).setdefault(p_, r)
        for p_, xs in o.get("dd", {}).items(): base.setdefault("dd", {}).setdefault(p_, xs)
        for p_ in o.get("dx", []):
            if base["d"].get(p_) == o["d"].get(p_) and p_ not in base.setdefault("dx", []): base["dx"].append(p_)
        if "au" not in base and "au" in o: base["au"] = o["au"]
        for f in ("sy", "an", "v"):
            for x in o.get(f, []):
                if x not in base.setdefault(f, []): base[f].append(x)
        if o.get("g") and not base.get("g"): base["g"] = o["g"]
        o["_merged"] = True

words, seen = [], set()
key_of = {}                                       # entry id -> key
defs_t, defs_m, pos, ex, reg, au, alt, dia, tok, sub, typ, cat, own, dex, dia2 = [], {}, {}, {}, {}, {}, {}, {}, {}, [], {}, {}, [], {}, {}
used = set()
collisions = 0
for e in D["E"]:
    if e.get("_merged"):
        continue
    if "r" not in e:
        key_of[e["i"]] = e["h"] + "\t"
        continue
    c = codes_only(e["r"])
    if not c:
        key_of[e["i"]] = e["h"] + "\t"
        continue
    k = e["h"] + "\t" + c
    key_of[e["i"]] = k
    if k in seen:
        collisions += 1
        continue                                  # same characters + same reading: keep the first entry
    seen.add(k)
    words.append([e["h"], c])
    used.update(c.split())
    if needs_tokens(e["r"]): tok[k] = e["r"]
    if e.get("m"):
        lines = [m["t"] for m in e["m"]]
        text = lines[0] if len(lines) == 1 else "\n".join(f"{i + 1}. {t}" for i, t in enumerate(lines))
        defs_m[k] = len(defs_t); defs_t.append(text)
        if any(m["p"] for m in e["m"]): pos[k] = "|".join(m["p"] for m in e["m"])
        if any(m.get("x") for m in e["m"]):
            ex[k] = [m.get("x", []) for m in e["m"]]
            for m in e["m"]:
                for x in m.get("x", []):
                    used.update(re.findall(r"\{\^?([^}]+)\}", x[1]))
    if e.get("g"): reg[k] = e["g"]
    if "au" in e: au[k] = e["au"]
    if e.get("s"): sub.append(k)
    if e["t"] != 0: typ[k] = e["t"]
    if e["t"] == 5: own.append(k)
    if e.get("c"): cat[k] = e["c"]
    for a, label in e.get("a", []):
        ac = codes_only(a)
        if ac and ac != c:
            alt.setdefault(k, []).append([ac, label] + ([a] if needs_tokens(a) else []))
            used.update(ac.split())
    for p, r in e.get("d", {}).items():
        rc = codes_only(r)
        if rc and rc != c:
            dia.setdefault(k, {})[p] = rc
            used.update(rc.split())
            if p in e.get("dx", []): dex[k] = dex.get(k, "") + p     # MOE states it (not worked out by rule)
    for p, xs in e.get("dd", {}).items():                        # the place also says it these ways
        cs = [x for x in (codes_only(x) for x in xs) if x]
        if cs:
            dia2.setdefault(k, {})[p] = cs
            for x in cs: used.update(x.split())

for o, b_ in merged_into.items(): key_of[o] = key_of[b_]

# synonyms / antonyms (per meaning, plus whole-word links)
def links(field):
    out = {}
    for e in D["E"]:
        if e.get("_merged"): continue
        k = key_of.get(e["i"])
        if not k or k.endswith("\t") or k not in defs_m and field not in e and not any(field in m for m in e.get("m", [])):
            continue
        rec = {}
        for i, m in enumerate(e.get("m", [])):
            t = [key_of[x] for x in m.get(field, []) if x in key_of]
            if t: rec[str(i)] = t
        t = [key_of[x] for x in e.get(field, []) if x in key_of]
        if t: rec["e"] = t
        if rec and k not in out: out[k] = rec
    return out
sy, an = links("sy"), links("an")

# variant characters
var = collections.defaultdict(list)
for e in D["E"]:
    k = key_of.get(e["i"])
    if not k or k.endswith("\t"): continue
    for v in e.get("v", []):
        if k not in var[v]: var[v].append(k)

# 各地講法
cmp = []
for zh, items in D["cmp"]:
    row = []
    for p, han, r in items:
        rc = codes_only(r)
        row.append([p, han, rc or ""])
        if rc: used.update(rc.split())
    cmp.append([zh, row])

# names / surnames
def names(src):
    out = {}
    for ch, lst in src.items():
        row = []
        for r, t in lst:
            rc = codes_only(r)
            if rc:
                row.append([rc, t]); used.update(rc.split())
        if row: out[ch] = row
    return out
nm, sr = names(D["names"]), names(D["sur"])

# 華語 glossary, from the dictionary itself:
#  1) the short 華語 equivalent at the start of each meaning ("數目。" -> 數目)
#  2) word-level examples: 台語 word / its 華語 translation ("一睏仔" -> 一下子, marked ~)
HAN = re.compile(r"^[\u3400-\u9fff\uf900-\ufaff\U00020000-\U0003134f]+$")
def terms_of(text):
    out = []
    for t in re.split(r"[、，,；;]", text):
        t = t.strip().strip("「」『』（）()")
        if 1 <= len(t) <= 6 and HAN.match(t): out.append(t)
    return out
G = collections.defaultdict(dict)
for e in D["E"]:
    if e.get("_merged") or e["i"] not in key_of: continue
    k = key_of[e["i"]]
    if k.endswith("\t") or k not in seen: continue
    for m in e.get("m", []):
        g = m["t"].split("。")[0]
        if len(g) <= 12:
            for t in terms_of(g): G[k].setdefault(t, 1)
        for x in m.get("x", []):
            w, zh = x[0], x[2]
            if HAN.match(w) and len(w) <= 5 and len(zh) <= 6 and HAN.match(zh):
                xk = w + "\t" + " ".join(re.findall(r"\{\^?([^}]+)\}", x[1]))
                if xk in seen: G[xk].setdefault(zh, 2)
gl = {k: "|".join(t if s_ == 1 else "~" + t for t, s_ in v.items()) for k, v in G.items()}
# + the 華語 words of 詞彙比較
for zh, row in cmp:
    for p, han, rc in row:
        k = han + "\t" + rc
        if k in seen:
            terms = gl.get(k, "").split("|") if gl.get(k) else []
            if zh not in [t.lstrip("~") for t in terms]: terms.append(zh)
            gl[k] = "|".join(terms)

for c in sorted(used):
    try:
        parse(c) and code_to_haolo(c)
    except Exception: print("BAD CODE", repr(c))
syl = {c: [code_to_zhuyin(c), code_to_haolo(c)] for c in sorted(used) if parse(c)}
tl = {}
for c in syl:
    m = code_to_tl(c)
    num = re.sub(r"[̀-ͯ]", "", __import__("unicodedata").normalize("NFD", m)) + c[-1]
    tl[c] = [m, num]
pj = {c: code_to_poj(c) for c in syl}

# reading in context: for characters with several readings, how often each reading appears in the
# dictionary's example sentences, and next to which characters (helps the converter pick the reading)
HANC = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\U00020000-\U0003134f\u3007]")
single = collections.defaultdict(set)
for h, c in words:
    if len(h) == 1: single[h].add(c)
amb = {h for h, cs in single.items() if len(cs) > 1}
cu, cl, cr = collections.Counter(), collections.Counter(), collections.Counter()
for senses in ex.values():
    for xs in senses:
        for x in xs:
            hs = HANC.findall(x[0]); cs = re.findall(r"\{\^?([^}]+)\}", x[1])
            if len(hs) != len(cs): continue
            for i, (h, c) in enumerate(zip(hs, cs)):
                if h not in amb or c not in single[h]: continue
                cu[h + "\t" + c] += 1
                if i > 0: cl[hs[i - 1] + "\t" + h + "\t" + c] += 1
                if i + 1 < len(hs): cr[h + "\t" + c + "\t" + hs[i + 1]] += 1
ctx = {"u": dict(cu), "l": dict(cl), "r": dict(cr)}

# how common each character is: ln(count) in rime-essay
counts = collections.Counter()
for line in open(ESSAY, encoding="utf-8"):
    p_ = line.rstrip("\n").split("\t")
    if len(p_) >= 2 and len(p_[0]) == 1 and p_[1].isdigit(): counts[p_[0]] += int(p_[1])
chars = {ch for h, _ in words for ch in h}
freq = {ch: round(math.log(counts[ch]), 1) for ch in sorted(chars) if counts[ch] > 0}

out = {
    "v": 2, "words": words, "syl": syl, "tl": tl, "pj": pj,
    "defs": {"t": defs_t, "m": defs_m}, "pos": pos, "ex": ex, "reg": reg, "own": own, "au": au,
    "gl": [[k, v] for k, v in gl.items()], "freq": freq, "dex": dex, "ctx": ctx, "dia2": dia2,
    "places": D["places"], "g1": D["g1"], "types": D["types"], "cats": D["cats"],
    "alt": alt, "dia": dia, "tok": tok, "sub": sub, "typ": typ, "cat": cat,
    "sy": sy, "an": an, "var": var, "cmp": cmp, "names": nm, "sur": sr,
}
json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print("words", len(words), "collisions", collisions, "syllables", len(syl))
print("defs", len(defs_t), "examples", sum(len(x) for v in ex.values() for x in v), "audio", len(au))
print("alt", len(alt), "dialect", len(dia), "tokens", len(tok), "sub", len(sub), "syn", len(sy), "ant", len(an))
print("variants", len(var), "cmp", len(cmp), "names", len(nm), "surnames", len(sr), "gl", len(gl), "cat", len(cat))
