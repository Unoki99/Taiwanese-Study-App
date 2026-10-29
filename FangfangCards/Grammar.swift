import Foundation

// 文法: how normal a sentence is, judged by patterns learned from the MOE dictionary's example sentences
// (tools/build_grammar.py makes grammar.json). Not AI: counts of which word class follows which, and
// what usually comes before and after common words.
//
// A sentence is split into words the same way as 轉換 (漢字 or 羅馬字). A word with several classes gets
// the one that fits best (every combination is tried). Each step between neighbours is scored by
//  - the class pattern (the two classes before it), and
//  - for common words: which class usually follows this word, and which class usually comes before the next.
// Using a word in a class it's rarely used in costs points too. The score is compared with the dictionary's
// own sentences.

struct GrammarRaw: Decodable, Sendable {
    let tags: [String]
    let big: [String: Int], uni: [String: Int], tri: [String: Int], bi2: [String: Int]
    let bigb: [String: Int], unib: [String: Int]
    let next: [String: [String: Int]], prev: [String: [String: Int]]
    let gold: [String: [String: Int]]
    let ref: [Double]
}

/// one word of the sentence being checked
struct GToken: Hashable, Sendable {
    let text: String          // 漢字 (or what was typed, if it isn't a dictionary word)
    let key: String?          // dictionary key
    let punct: Bool
}

struct GrammarResult: Sendable {
    let tokens: [GToken]
    let tags: [String]
    let score: Double         // 0–1: share of the dictionary's sentences that score lower
    /// the oddest step: between token index-1 and index (0 = the start, tokens.count = the end)
    let worst: Int?
    let suggestion: [GToken]?
    let suggestionScore: Double?
    var level: Int { score >= 0.3 ? 2 : (score >= 0.1 ? 1 : 0) }   // 2 ✅  1 🤔  0 ❌
}

final class Grammar: @unchecked Sendable {
    static let S = "<s>", E = "</s>"
    let raw: GrammarRaw
    let dict: Dict
    private let V: Double
    private var nextTot: [String: Double] = [:], prevTot: [String: Double] = [:]

    init(_ raw: GrammarRaw, dict: Dict) {
        self.raw = raw; self.dict = dict
        V = Double(raw.tags.count + 1)
        for (w, c) in raw.next { nextTot[w] = Double(c.values.reduce(0, +)) }
        for (w, c) in raw.prev { prevTot[w] = Double(c.values.reduce(0, +)) }
    }

    private static let lock = NSLock()
    private static var rawCache: GrammarRaw?
    private static var cache: Grammar?

    /// grammar.json is read once; the checker is remade only when the dictionary is reloaded
    static func load(dict: Dict) -> Grammar? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache, c.dict === dict { return c }
        if rawCache == nil {
            guard let url = Bundle.main.url(forResource: "grammar", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode(GrammarRaw.self, from: data) else { return nil }
            rawCache = raw
        }
        let g = Grammar(rawCache!, dict: dict)
        cache = g
        return g
    }

    // MARK: classes of a word

    private func norm(_ s: String, _ key: String) -> String {
        if s == "動詞" && dict.isVerbWithNoun(key) { return "離合詞" }
        if s == "助動詞" { return "動詞" }
        return s
    }

    /// the classes a word can have, weighted by how it's used (its meanings, and its own example sentences)
    func cands(_ t: GToken) -> [String: Double] {
        if t.punct { return ["標點": 1] }
        guard let k = t.key, let pos = dict.raw.pos[k] else { return ["?": 1] }
        var c: [String: Double] = [:]
        for s in pos.split(separator: "|", omittingEmptySubsequences: true) { c[norm(String(s), k), default: 0] += 1 }
        if c.isEmpty { return ["?": 1] }
        let g = raw.gold[k]
        for t in c.keys { c[t] = c[t]! * 0.5 + Double(g?[t] ?? 0) + 0.2 }
        return c
    }

    // MARK: scoring

    private func n(_ m: [String: Int], _ k: String) -> Double { Double(m[k] ?? 0) }

    private func logp3(_ a: String, _ b: String, _ c: String) -> Double {
        let p2 = (n(raw.big, b + "|" + c) + 0.1) / (n(raw.uni, b) + 0.1 * V)
        let ab = n(raw.bi2, a + "|" + b)
        if ab == 0 { return log(p2) }
        let w = ab / (ab + 5)
        return log(w * n(raw.tri, a + "|" + b + "|" + c) / ab + (1 - w) * p2)
    }
    private func pb(_ t: String, _ tp: String) -> Double {
        (n(raw.bigb, t + "|" + tp) + 0.1) / (n(raw.unib, t) + 0.1 * V)
    }

    /// how normal it is that word wp (class tp, after class tpp) is followed by word w (class t)
    private func step(_ wp: String, _ tp: String, _ w: String, _ t: String, _ tpp: String) -> Double {
        let baseF = exp(logp3(tpp, tp, t))
        var f = baseF
        if let nf = nextTot[wp], nf > 0 {
            let lf = nf / (nf + 15)
            f = lf * (Double(raw.next[wp]?[t] ?? 0) + 0.05) / (nf + 0.05 * V) + (1 - lf) * baseF
        }
        var b = pb(t, tp)
        if let nb = prevTot[w], nb > 0 {
            let lb = nb / (nb + 15)
            b = lb * (Double(raw.prev[w]?[tp] ?? 0) + 0.05) / (nb + 0.05 * V) + (1 - lb) * pb(t, tp)
        }
        return 0.5 * (log(f) + log(b))
    }

    /// the best classes for the words, and the average score per step
    func tag(_ toks: [GToken]) -> (tags: [String], mean: Double) {
        typealias State = (score: Double, path: [String])
        var best: [String: (a: String, b: String, s: State)] = [Grammar.S + "|" + Grammar.S: (Grammar.S, Grammar.S, (0, []))]
        var prevWord = Grammar.S
        for tok in toks {
            let lay = cands(tok)
            let tot = lay.values.reduce(0, +)
            var nb: [String: (a: String, b: String, s: State)] = [:]
            for (_, v) in best {
                for (t, cnt) in lay {
                    let sc = v.s.score + step(prevWord, v.b, tok.text, t, v.a) + log(cnt / tot)
                    let id = v.b + "|" + t
                    if nb[id] == nil || sc > nb[id]!.s.score { nb[id] = (v.b, t, (sc, v.s.path + [t])) }
                }
            }
            best = nb
            prevWord = tok.text
        }
        var top: (Double, [String]) = (-.infinity, [])
        for (_, v) in best {
            let sc = v.s.score + step(prevWord, v.b, Grammar.E, Grammar.E, v.a)
            if sc > top.0 { top = (sc, v.s.path) }
        }
        return (top.1, top.0 / Double(toks.count + 1))
    }

    /// share of the dictionary's own sentences that score lower
    func percentile(_ mean: Double) -> Double {
        var lo = 0, hi = raw.ref.count
        while lo < hi { let mid = (lo + hi) / 2; if raw.ref[mid] < mean { lo = mid + 1 } else { hi = mid } }
        return Double(lo) / Double(max(raw.ref.count - 1, 1))
    }

    /// each step's score (to find the oddest one)
    func steps(_ toks: [GToken], _ tags: [String]) -> [Double] {
        let W = [Grammar.S] + toks.map(\.text) + [Grammar.E]
        let T = [Grammar.S] + tags + [Grammar.E], TT = [Grammar.S, Grammar.S] + tags + [Grammar.E]
        var out: [Double] = []
        for i in 0..<(W.count - 1) {
            var e = 0.0
            if i < toks.count { let lay = cands(toks[i]); e = log((lay[tags[i]] ?? 0.01) / lay.values.reduce(0, +)) }
            out.append(step(W[i], T[i], W[i + 1], T[i + 1], TT[i]) + e)
        }
        return out
    }

    // MARK: a sentence

    /// split text into words, the same way as 轉換 (the punctuation mark at the very end is left out)
    func tokens(_ text: String) -> [GToken] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?.…"))
        let res = ConvertEngine(dict: dict).convert(t)
        var out: [GToken] = []
        for it in res.items {
            if it.space || it.newline { continue }
            if let r = it.raw {
                if ConvertEngine.isPunct(r) { out.append(GToken(text: "，", key: nil, punct: true)) }
                else { out.append(GToken(text: r, key: nil, punct: false)) }
                continue
            }
            let key = dict.keyOf(it.current)
            let han = key.map { Dict.hanOf($0) } ?? it.current.han ?? ""
            out.append(GToken(text: han, key: key, punct: false))
        }
        return out
    }

    func analyse(_ text: String) -> GrammarResult? {
        let toks = tokens(text)
        guard !toks.isEmpty else { return nil }
        let (tags, mean) = tag(toks)
        let pct = percentile(mean)
        guard pct < 0.3 else { return GrammarResult(tokens: toks, tags: tags, score: pct, worst: nil, suggestion: nil, suggestionScore: nil) }
        let st = steps(toks, tags)
        let worst = st.indices.min { st[$0] < st[$1] }
        // a better order: one word moved somewhere else
        var best: ([GToken], Double)? = nil
        if toks.count <= 14 {
            for i in toks.indices {
                for j in toks.indices where i != j {
                    var t2 = toks
                    let x = t2.remove(at: i)
                    t2.insert(x, at: j)
                    let p = percentile(tag(t2).mean)
                    if best == nil || p > best!.1 { best = (t2, p) }
                }
            }
        }
        let good = best.flatMap { $0.1 > pct + 0.15 ? $0 : nil }
        return GrammarResult(tokens: toks, tags: tags, score: pct, worst: worst, suggestion: good?.0, suggestionScore: good?.1)
    }
}
