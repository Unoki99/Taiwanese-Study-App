# The syllable code ("anchor") used by every 方方 tool, and conversions to/from it.
#   code = initial? + N? (nasal) + vowels + final? + tone
#   initials  p P b t T d k K g c C z s h      (P = ph, T = th, K = kh, c = ts, C = tsh, z = j, d = l/n, b = b/m, g = g/ng)
#   vowels    i u a o(=oo) ø(=o) e I(=ai) U(=au)  + dialect: ɨ (ir)  ə (er)  ɵ (or)     ere = əe
#   finals    B (m/p)  D (n/t)  G (ng/k)          tones 1–9 (4/8 = checked; no final + 4/8 = -h)
import re, unicodedata as U

CODE_RE = re.compile(r"^([pPbtTdkKgcCzsh]?)(N?)([iuaoøeIUɨəɵ]*)([BDG]?)([1-9])$")
def parse(code):
    m = CODE_RE.match(code)
    if not m: return None
    ini, nas, vow, fin, tone = m.groups()
    if not vow and not fin: return None
    return ini, bool(nas), vow, fin, int(tone)

# ---------------------------------------------------------------- Tâi-lô -> code
TL_TONE = {"́": 2, "̀": 3, "̂": 5, "̌": 6, "̄": 7, "̍": 8, "̋": 9}

def tl_split(s):
    """one Tâi-lô syllable with diacritics -> (lowercase letters, tone, capitalised)"""
    tone, out = None, []
    for ch in U.normalize("NFD", s):
        if ch in TL_TONE: tone = TL_TONE[ch]
        else: out.append(ch)
    w = U.normalize("NFC", "".join(out))
    cap = w[:1].isupper()
    w = w.lower()
    if tone is None:
        tone = 4 if re.search(r"[ptkh]$", w) else 1
    return w, tone, cap

TL_INI = [("tsh", "C"), ("ts", "c"), ("ph", "P"), ("th", "T"), ("kh", "K"), ("ng", "gN"),
          ("p", "p"), ("b", "b"), ("t", "t"), ("k", "k"), ("g", "g"), ("h", "h"), ("s", "s"),
          ("j", "z"), ("l", "d"), ("m", "bN"), ("n", "dN")]
TL_V = [("ir", "ɨ"), ("er", "ə"), ("or", "ɵ"), ("ai", "I"), ("au", "U"), ("oo", "o"),
        ("a", "a"), ("e", "e"), ("i", "i"), ("o", "ø"), ("u", "u")]

def tl_to_code(w, tone):
    m = re.fullmatch(r"(tsh|ts|ph|th|kh|p|b|t|k|g|h|s|j|l|m|n)?(m|ng)(h?)", w)
    if m:                                               # syllabic m / ng: hm, mn̂g, tshng, hmh
        if m.group(3) and tone not in (4, 8): return None
        i = dict(TL_INI)[m.group(1)][:1] if m.group(1) else ""
        return f"{i}{'B' if m.group(2) == 'm' else 'G'}{tone}"
    ini = ""
    for t, c in TL_INI:
        if w.startswith(t) and len(w) > len(t):
            ini, w = c, w[len(t):]
            break
    nasal = False
    if ini.endswith("N"):
        ini = ini[0]
        if re.match(r"^[aeiou]", w): nasal = True
    if w.endswith("nnh"): nasal, w = True, w[:-3] + "h"
    elif w.endswith("nn"): nasal, w = True, w[:-2]
    fin = ""
    for t, c in (("ng", "G"), ("m", "B"), ("n", "D"), ("p", "B"), ("t", "D"), ("k", "G"), ("h", "")):
        if w.endswith(t) and len(w) > len(t):
            fin, w = c, w[: -len(t)]
            break
    vow, rest = "", w
    while rest:
        for t, c in TL_V:
            if rest.startswith(t):
                vow += c; rest = rest[len(t):]; break
        else:
            return None
    if not vow: return None
    if vow == "i" and fin == "G": vow = "iø"           # ing / ik
    if vow in ("ø", "iø") and fin in ("G", "B") and vow != "iø": vow = "o"   # ong ok om op
    if vow == "iø" and fin == "G" and "io" in w: vow = "io"                  # iong / iok
    if nasal and vow.endswith("ø"): vow = vow[:-1] + "o"                     # onn = oonn
    return f"{ini}{'N' if nasal else ''}{vow}{fin}{tone}"

# ---------------------------------------------------------------- code -> 方音
ZY_INI = {"p": "ㄅ", "P": "ㄆ", "b": "ㆠ", "t": "ㄉ", "T": "ㄊ", "d": "ㄌ", "k": "ㄍ", "K": "ㄎ",
          "g": "ㆣ", "h": "ㄏ", "c": "ㄗ", "C": "ㄘ", "s": "ㄙ", "z": "ㆡ"}
ZY_PAL = {"c": "ㄐ", "C": "ㄑ", "s": "ㄒ", "z": "ㆢ"}
ZY_NASINI = {"b": "ㄇ", "d": "ㄋ", "g": "ㄫ"}
ZY_V = {"i": "ㄧ", "u": "ㄨ", "a": "ㄚ", "o": "ㆦ", "ø": "ㄜ", "e": "ㆤ", "I": "ㄞ", "U": "ㄠ",
        "ɨ": "ㆨ", "ə": "ㄜ", "ɵ": "ㄜ"}
ZY_NAS = {"ㄧ": "ㆪ", "ㄨ": "ㆫ", "ㄚ": "ㆩ", "ㆦ": "ㆧ", "ㆤ": "ㆥ", "ㄞ": "ㆮ", "ㄠ": "ㆯ"}
ZY_TONE = {1: "ˉ", 2: "ˋ", 3: "˪", 4: "", 5: "ˊ", 6: "꜕", 7: "˫", 8: "̇", 9: "ꜘ"}

def code_to_zhuyin(code):
    """方音 for 通行. (With a place chosen, Tâi-lô o — code ø — is shown as ㄛ instead of ㄜ.)"""
    p = parse(code)
    if not p: return None
    ini, nas, vow, fin, tone = p
    stop = tone in (4, 8)
    out = []
    if ini:
        if ini in ZY_NASINI and ((nas and vow) or not vow):
            out.append(ZY_NASINI[ini]); nas = False
        elif vow[:1] in ("i", "ɨ") and ini in ZY_PAL and vow[:1] == "i":
            out.append(ZY_PAL[ini])
        else:
            out.append(ZY_INI[ini])
    v = list(vow)
    if stop and fin == "G" and vow == "iø": v = ["i"]
    syms = []
    for i, x in enumerate(v):
        if x == "e" and i > 0 and v[i - 1] == "ə": syms.append("ㄝ")     # ere = ㄜㄝ
        else: syms.append(ZY_V[x])
    if nas and syms: syms[-1] = ZY_NAS.get(syms[-1], syms[-1])
    if stop:
        f = {"B": "ㆴ", "D": "ㆵ", "G": "ㆻ", "": "ㆷ"}[fin]
        if not vow and fin == "B": f = "ㆬㆷ"
        if not vow and fin == "G": f = "ㆭㆷ"
        out += syms + [f]
    else:
        last = v[-1] if v else ""
        if fin == "B" and last in ("a", "o"): syms[-1] = {"a": "ㆰ", "o": "ㆱ"}[last]
        elif fin == "D" and last == "a": syms[-1] = "ㄢ"
        elif fin == "G" and last == "a": syms[-1] = "ㄤ"
        elif fin == "G" and last == "o": syms[-1] = "ㆲ"
        elif fin == "G" and vow == "iø": syms = ["ㄧ", "ㄥ"]
        elif fin: syms.append({"B": "ㆬ", "D": "ㄣ", "G": "ㆭ"}[fin])
        out += syms
    return "".join(out) + ZY_TONE[tone]

# ---------------------------------------------------------------- code -> 皓羅
HL_INI = {"p": "p", "P": "ph", "b": "b", "t": "t", "T": "th", "d": "l", "k": "k", "K": "kh",
          "g": "g", "h": "h", "c": "z", "C": "c", "s": "s", "z": "ł"}
HL_PAL = {"c": "j", "C": "q", "s": "x", "z": "ł"}
HL_NASINI = {"b": "m", "d": "n", "g": "ng"}
HL_V = {"i": "i", "u": "u", "a": "a", "o": "oo", "ø": "o", "e": "e", "I": "ai", "U": "au",
        "ɨ": "ir", "ə": "er", "ɵ": "o"}
HL_TONE = {1: "̍", 2: "̀", 3: "̣", 4: "̣", 5: "́", 6: "̱",
           7: "̄", 8: "̍", 9: "̋"}

def _mark_pos(body):
    for v in ("a", "oo", "o", "e"):
        if v in body: return body.index(v)
    if body in ("iu", "ui"): return 1
    return 0

def code_to_haolo(code):
    p = parse(code)
    if not p: return None
    ini, nas, vow, fin, tone = p
    stop = tone in (4, 8)
    head = ""
    if ini:
        if ini in HL_NASINI and ((nas and vow) or not vow):
            head = HL_NASINI[ini]
            if vow: nas = False
        elif vow[:1] == "i" and ini in HL_PAL:
            head = HL_PAL[ini]
        else:
            head = HL_INI[ini]
    v = list(vow)
    if fin == "G" and vow == "iø": v = ["i"]
    if "".join(v).endswith("əe"):                      # ere -> oe
        v = v[:-2] + ["ERE"]
    parts = ["oe" if x == "ERE" else HL_V[x] for x in v]
    if fin and v and v[-1] == "o": parts[-1] = "o"     # om ong op ok (not oo)
    if stop:
        tail = {"B": "p", "D": "t", "G": "k", "": "h"}[fin]
        if not vow: tail = {"B": "m", "G": "ng"}[fin] + "h"
    else:
        tail = {"B": "m", "D": "n", "G": "ng", "": ""}[fin]
    body = "".join(parts)
    if body:
        pos = _mark_pos(body)
        body = body[:pos + 1] + HL_TONE[tone] + body[pos + 1:]
    else:                                              # syllabic m / ng: mark on m / n
        tail = tail[0] + HL_TONE[tone] + tail[1:]
    return U.normalize("NFC", head + body + ("ⁿ" if nas else "") + tail)

# ---------------------------------------------------------------- code -> Tâi-lô / 白話字
TLM = {1: "", 2: "́", 3: "̀", 4: "", 5: "̂", 6: "̌", 7: "̄", 8: "̍", 9: "̋"}
TL_INI_OUT = {"p": "p", "P": "ph", "b": "b", "t": "t", "T": "th", "d": "l", "k": "k", "K": "kh",
              "g": "g", "h": "h", "c": "ts", "C": "tsh", "s": "s", "z": "j"}
TL_V_OUT = {"i": "i", "u": "u", "a": "a", "o": "oo", "ø": "o", "e": "e", "I": "ai", "U": "au",
            "ɨ": "ir", "ə": "er", "ɵ": "or"}

def _letters(code, poj=False):
    ini, nas, vow, fin, tone = parse(code)
    stop = tone in (4, 8)
    head = ""
    if ini:
        if ini in HL_NASINI and ((nas and vow) or not vow):
            head = HL_NASINI[ini]
            if vow: nas = False
        else:
            head = TL_INI_OUT[ini]
    v = list(vow)
    if fin == "G" and vow == "iø": v = ["i"]
    body = "".join(TL_V_OUT[x] for x in v)
    if fin and v and v[-1] == "o": body = body[:-2] + "o"
    if stop:
        tail = {"B": "p", "D": "t", "G": "k", "": "h"}[fin]
        if not vow: tail = {"B": "m", "G": "ng"}[fin] + "h"
    else:
        tail = {"B": "m", "D": "n", "G": "ng", "": ""}[fin]
    if fin == "G" and vow == "iø" and poj:
        body = "e"                                     # 白話字 eng / ek
    return head, body, tail, nas, tone

def code_to_tl(code):
    if not parse(code): return None
    head, body, tail, nas, tone = _letters(code)
    nn = "nn" if nas else ""
    if body:
        if "a" in body: pos = body.index("a")
        elif "oo" in body: pos = body.index("oo")
        elif "o" in body: pos = body.index("o")
        elif "e" in body: pos = body.index("e")
        elif body in ("iu", "ui"): pos = 1
        else: pos = 0
        body = body[:pos + 1] + TLM[tone] + body[pos + 1:]
        if tail.endswith("h") and nas: return U.normalize("NFC", head + body + tail[:-1] + nn + "h")
        return U.normalize("NFC", head + body + tail + nn)
    t = tail
    k = 1 if t.startswith("ng") else 0                  # ńg / ḿ
    t = t[:k + 1] + TLM[tone] + t[k + 1:] if k == 0 else t[:1] + TLM[tone] + t[1:]
    return U.normalize("NFC", head + t)

POJ_INI = {"ts": "ch", "tsh": "chh"}
def code_to_poj(code):
    if not parse(code): return None
    head, body, tail, nas, tone = _letters(code, poj=True)
    head = POJ_INI.get(head, head)
    body = body.replace("oo", "o͘")
    if body.startswith("ua") or "ua" in body: body = body.replace("ua", "oa")
    if "ue" in body: body = body.replace("ue", "oe")
    nn = "ⁿ" if nas else ""
    if body:
        b = body.replace("͘", "")
        # 白話字: oa / oe take the mark on o unless a consonant follows
        if "oai" in b: pos = b.index("oai") + 1
        elif ("oa" in b or "oe" in b) and not tail:
            pos = b.index("o")
        elif ("oa" in b or "oe" in b):
            pos = b.index("o") + 1
        elif "a" in b: pos = b.index("a")
        elif "o" in b: pos = b.index("o")
        elif "e" in b: pos = b.index("e")
        elif b == "iu": pos = 1
        else: pos = 0
        # map position back into the string that may contain the o͘ dot
        out, j = [], 0
        for ch in body:
            out.append(ch)
            if ch != "͘":
                if j == pos: out.append(TLM[tone])
                j += 1
        body = "".join(out)
        if tail == "h" and nas: return U.normalize("NFC", head + body + "h" + nn)
        return U.normalize("NFC", head + body + tail + nn)
    if head == "n":                                    # ńng (but mńg)
        return U.normalize("NFC", head[:1] + TLM[tone] + head[1:] + tail)
    return U.normalize("NFC", head + tail[:1] + TLM[tone] + tail[1:])
