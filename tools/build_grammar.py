# 方方詞卡 文法: learns word-class patterns from the MOE dictionary's example sentences.
#   python3 build_grammar.py FangfangCards/dict.json FangfangCards/grammar.json
#
# 1. Every example sentence is split into dictionary words (the template's dashes tell which syllables
#    belong together; inside a group, the longest dictionary words). Verbs that end in a noun (洗身軀, 食飯)
#    are their own class, 離合詞.
# 2. Each sentence is filed under one meaning of its headword, so the headword's class is known there.
#    Words with only one class are known too. The other words get the class that fits the patterns best
#    (two rounds: learn patterns, label, learn again).
# 3. Saved: how often each class follows the one (and two) before it, what class comes after / before
#    each common word, how each word is usually used, and how the dictionary's own sentences score
#    (to tell how normal a new sentence is).
import json, re, sys, collections, math, bisect

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
POS = D['pos']
KEYS = {w[0] + "\t" + w[1] for w in D['words']}
ALT = {}
for k, v in D['alt'].items():
    h = k.split("\t")[0]
    for a in v: ALT[h + "\t" + " ".join(x for x in a[0].split() if x != "_")] = k
PUNCT = set("，。！？；：、,.!?;:「」『』（）()…—")
ishan = lambda ch: '㐀' <= ch <= '鿿' or ch >= '\U00020000' or ch == '〇'
MAIN = lambda v: v.split('|')[0]
S, E = '<s>', '</s>'

def is_verb_with_noun(k):
    v = POS.get(k)
    if not v or '動詞' not in MAIN(v): return False
    h, c = k.split("\t"); hs, cs = list(h), c.split()
    if len(hs) != len(cs) or len(hs) < 2: return False
    for L in range(1, len(hs)):
        kk = "".join(hs[-L:]) + "\t" + " ".join(cs[-L:])
        if kk in KEYS and '名詞' in MAIN(POS.get(kk, '')): return True
    return False
VN = {k for k in POS if is_verb_with_noun(k)}

def norm(s, k):
    if s == '動詞' and k in VN: return '離合詞'
    if s == '助動詞': return '動詞'
    return s

def classes_of(k):
    c = collections.Counter()
    for s in POS.get(k, '').split('|'):
        if s: c[norm(s, k)] += 1
    return c

def segment(han, tpl):
    ms = list(re.finditer(r'\{\^?([^}]*)\}', tpl))
    codes = [m.group(1) for m in ms]
    seps, prev = [], 0
    for m in ms: seps.append(tpl[prev:m.start()]); prev = m.end()
    chars = [ch for ch in han if ishan(ch)]
    if len(codes) != len(chars) or not codes: return None
    groups, out = [], []
    for n in range(len(codes)):
        if n > 0 and seps[n] in ('-', '--'): groups[-1].append(n)
        else: groups.append([n])
    for g in groups:
        if any(ch in PUNCT for ch in seps[g[0]]): out.append(('，', None, True))
        a = 0
        while a < len(g):
            step, found = 1, None
            for L in range(len(g) - a, 0, -1):
                seg = g[a:a + L]
                k = "".join(chars[i] for i in seg) + "\t" + " ".join(codes[i] for i in seg)
                if k in KEYS: found = k; step = L; break
                if k in ALT: found = ALT[k]; step = L; break
            seg = g[a:a + step]
            out.append(("".join(chars[i] for i in seg), found, False))
            a += step
    return out

sents = []
for k, senses in D['ex'].items():
    pos_list = POS.get(k, '').split('|')
    for si, exs in enumerate(senses):
        gold = norm(pos_list[si], k) if si < len(pos_list) and pos_list[si] else None
        for e in exs:
            if len(e) < 2: continue
            toks = segment(e[0], e[1])
            if not toks: continue
            head = next((i for i, t in enumerate(toks) if t[1] == k), None)
            sents.append({'toks': toks, 'head': head, 'gold': gold, 'entry': k})

GOLD = collections.defaultdict(collections.Counter)
for s in sents:
    if s['head'] is not None and s['gold']: GOLD[s['entry']][s['gold']] += 1

def cands(tok):
    text, k, punct = tok
    if punct: return collections.Counter({'標點': 1})
    c = classes_of(k) if k else collections.Counter()
    if not c: return collections.Counter({'?': 1})
    g = GOLD.get(k)
    out = collections.Counter()
    for t, n in c.items(): out[t] = n * 0.5 + (g[t] if g else 0) + 0.2
    return out

TAGS = sorted({t for s in sents for tok in s['toks'] for t in cands(tok)} | {'名詞', '動詞'})
V = len(TAGS) + 1
big, uni, TRI, BI2 = (collections.Counter() for _ in range(4))

def logp(a, b): return math.log((big[(a, b)] + 0.1) / (uni[a] + 0.1 * V))
def logp3(a, b, c):
    p2 = (big[(b, c)] + 0.1) / (uni[b] + 0.1 * V)
    if BI2[(a, b)] == 0: return math.log(p2)
    w = BI2[(a, b)] / (BI2[(a, b)] + 5)
    return math.log(w * TRI[(a, b, c)] / BI2[(a, b)] + (1 - w) * p2)

LAM = 0.4
def viterbi(toks, fixed=None):
    best = {(S, S): (0.0, [])}
    for i, tok in enumerate(toks):
        c = collections.Counter({fixed[i]: 1}) if fixed and i in fixed else cands(tok)
        tot = sum(c.values()); nb = {}
        for (a, b), v in best.items():
            for t, n in c.items():
                sc = v[0] + (logp3(a, b, t) if TRI else logp(b, t)) + LAM * math.log(n / tot)
                if (b, t) not in nb or sc > nb[(b, t)][0]: nb[(b, t)] = (sc, v[1] + [t])
        best = nb
    return max(((v[0] + (logp3(a, b, E) if TRI else logp(b, E)), v[1]) for (a, b), v in best.items()), key=lambda x: x[0])[1]

# start from what's certain
for s in sents:
    tags = []
    for i, tok in enumerate(s['toks']):
        c = cands(tok)
        if i == s['head'] and s['gold']: tags.append(s['gold'])
        elif len(c) == 1: tags.append(next(iter(c)))
        else: tags.append(None)
    seq = [S] + tags + [E]
    for a, b in zip(seq, seq[1:]):
        if a is not None and b is not None: big[(a, b)] += 1; uni[a] += 1
for rnd in range(2):
    all_tags = [viterbi(s['toks'], {s['head']: s['gold']} if s['head'] is not None and s['gold'] else None) for s in sents]
    big.clear(); uni.clear(); TRI.clear(); BI2.clear()
    for tags in all_tags:
        seq = [S, S] + tags + [E]
        for a, b, c in zip(seq, seq[1:], seq[2:]):
            big[(b, c)] += 1; uni[b] += 1; TRI[(a, b, c)] += 1; BI2[(a, b)] += 1
    print("round", rnd + 1, file=sys.stderr)

NEXT = collections.defaultdict(collections.Counter)
PREV = collections.defaultdict(collections.Counter)
BIGB = collections.Counter(); UNIB = collections.Counter()
for s, tags in zip(sents, all_tags):
    ws = ['<s>'] + [t[0] for t in s['toks']] + ['</s>']
    ts = [S] + tags + [E]
    for i in range(len(ws) - 1):
        NEXT[ws[i]][ts[i + 1]] += 1
        PREV[ws[i + 1]][ts[i]] += 1
        BIGB[(ts[i + 1], ts[i])] += 1; UNIB[ts[i + 1]] += 1
# only words seen at least 3 times keep their own neighbours (the app gets the same, so scores match)
for M in (NEXT, PREV):
    for w in [w for w, c in M.items() if sum(c.values()) < 3]: del M[w]

# ---- scoring (the app does exactly the same)
def pf(tp, t): return (big[(tp, t)] + 0.1) / (uni[tp] + 0.1 * V)
def pb(t, tp): return (BIGB[(t, tp)] + 0.1) / (UNIB[t] + 0.1 * V)
def step(wp, tp, w, t, tpp):
    base_f = math.exp(logp3(tpp, tp, t))
    nf = sum(NEXT[wp].values()); lf = nf / (nf + 15)
    f = lf * (NEXT[wp][t] + 0.05) / (nf + 0.05 * V) + (1 - lf) * base_f if nf else base_f
    nb = sum(PREV[w].values()); lb = nb / (nb + 15)
    b = lb * (PREV[w][tp] + 0.05) / (nb + 0.05 * V) + (1 - lb) * pb(t, tp) if nb else pb(t, tp)
    return 0.5 * (math.log(f) + math.log(b))
def score(words, layers):
    best = {(S, S): 0.0}
    W = ['<s>'] + words
    for i, lay in enumerate(layers):
        tot = sum(lay.values()); nb = {}
        for (a, b), v in best.items():
            for t, n in lay.items():
                sc = v + step(W[i], b, W[i + 1], t, a) + math.log(n / tot)
                if (b, t) not in nb or sc > nb[(b, t)]: nb[(b, t)] = sc
        best = nb
    return max(v + step(W[-1], b, '</s>', E, a) for (a, b), v in best.items()) / (len(words) + 1)

ref = sorted(score([t[0] for t in s['toks']], [cands(t) for t in s['toks']]) for s in sents[::3])
quant = [round(ref[min(len(ref) - 1, int(i * len(ref) / 200))], 4) for i in range(201)]

keep = lambda m: {w: dict(c) for w, c in m.items() if sum(c.values()) >= 3}
out = {
    "v": 1, "tags": TAGS,
    "big": {a + "|" + b: n for (a, b), n in big.items()},
    "uni": dict(uni),
    "tri": {a + "|" + b + "|" + c: n for (a, b, c), n in TRI.items()},
    "bi2": {a + "|" + b: n for (a, b), n in BI2.items()},
    "bigb": {a + "|" + b: n for (a, b), n in BIGB.items()},
    "unib": dict(UNIB),
    "next": keep(NEXT), "prev": keep(PREV),
    "gold": {k: dict(c) for k, c in GOLD.items()},
    "ref": quant,
}
json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print("grammar: sentences", len(sents), "classes", len(TAGS), "words with neighbours", len(out["next"]))
