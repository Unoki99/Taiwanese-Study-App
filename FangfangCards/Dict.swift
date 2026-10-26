import Foundation

// The full 方方 dictionary (the same data as the website), for the native 轉換 tab.
// A word is identified by its key "漢字\tcodes" (codes = the 通行 reading as syllable codes).

struct CmpRow: Decodable {
    let place: Int
    let han: String
    let codes: String
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        place = try c.decode(Int.self)
        han = try c.decode(String.self)
        codes = try c.decode(String.self)
    }
}

struct CmpEntry: Decodable {
    let zh: String
    let rows: [CmpRow]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        zh = try c.decode(String.self)
        rows = try c.decode([CmpRow].self)
    }
}

/// how often each reading of a character appears in the example sentences, alone (u) and after (l) / before (r)
/// another character: keys "字\tcode", "前字\t字\tcode", "字\tcode\t後字"
struct CtxRaw: Decodable {
    let u: [String: Int]
    let l: [String: Int]
    let r: [String: Int]
}

struct DefsRaw: Decodable {
    let t: [String]
    let m: [String: Int]
}

struct DictRaw: Decodable {
    let words: [[String]]
    let syl: [String: [String]]
    let tl: [String: [String]]
    let pj: [String: String]
    let defs: DefsRaw
    let pos: [String: String]
    let ex: [String: [[[String]]]]
    let reg: [String: String]
    let own: [String]
    let au: [String: Int]
    let gl: [[String]]
    let freq: [String: Double]
    let places: [String]
    let alt: [String: [[String]]]
    let dia: [String: [String: String]]
    let tok: [String: String]
    let sub: [String]
    let typ: [String: Int]
    let sy: [String: [String: [String]]]
    let an: [String: [String: [String]]]
    let variants: [String: [String]]
    let cmp: [CmpEntry]
    let names: [String: [[String]]]
    let sur: [String: [[String]]]
    let types: [String]?
    let cats: [String]?
    let cat: [String: [Int]]?
    let ctx: CtxRaw?
    let dex: [String: String]?          // places whose reading MOE states (the others are worked out by rule)

    enum CodingKeys: String, CodingKey {
        case words, syl, tl, pj, defs, pos, ex, reg, own, au, gl, freq, places, alt, dia, tok, sub, typ, sy, an, cmp, names, sur, types, cats, cat, dex, ctx
        case variants = "var"
    }
}

/// one meaning of a word, ready to show
struct DictSense {
    let n: Int
    let pos: String
    let text: String
    let ex: [[String]]          // [漢字, template, 華語, audio name]
    let syn: [String]           // keys
    let ant: [String]
}

/// a reading choice for a word in the converter
struct Opt: Equatable {
    var han: String?
    var codes: [String]?
    var parent: String? = nil   // the word's key, for alternative readings and variant characters
    var label: String? = nil    // 又 / 俗 / 合
    var tokens: String? = nil
}

final class Dict: @unchecked Sendable {
    let raw: DictRaw
    let baseKeys: Set<String>
    let own: Set<String>
    let subst: Set<String>
    private(set) var hanMap: [String: [String]] = [:]        // 漢字 -> codes strings
    private(set) var codeMap: [String: [String]] = [:]       // codes string -> 漢字
    private(set) var hanAlt: [String: [Opt]] = [:]
    private(set) var altParent: [String: String] = [:]
    private(set) var maxHan = 1
    private(set) var maxSyl = 1
    // input
    private(set) var zyRev: [String: [String]] = [:]
    private(set) var zyRev0: [String: [String]] = [:]
    private(set) var latRev: [String: [String]] = [:]
    private(set) var tlRev: [String: [String]] = [:]
    private(set) var pojRev: [String: [String]] = [:]
    private(set) var maxZy = 1
    private(set) var plainRev: [String: [String]] = [:]     // spelling without tone -> codes (皓羅, 台羅, 白話字)
    // 華語 lookup
    private(set) var gl: [String: [(t: String, ex: Bool)]] = [:]
    private(set) var termIndex: [String: [String]] = [:]
    private var pairCount: [String: Int] = [:]
    // 分類
    private(set) var catWords: [Int: [String]] = [:]
    var catCounts: [Int: Int] { catWords.mapValues { $0.count } }

    static let taigiCommon = Set("阮咱恁怹伊我你佇欲咧予共佮毋袂會閣攏遮遐啥厝媠囝仔个的矣嘛猶抑煞較足誠真去來看講聽想做食飯人有無是佗遐爾按怎彼這".map { String($0) })

    init(_ r: DictRaw) {
        raw = r
        baseKeys = Set(r.words.map { $0[0] + "\t" + $0[1] })
        own = Set(r.own)
        subst = Set(r.sub)

        func push(_ m: inout [String: [String]], _ k: String, _ v: String) {
            if var a = m[k] { if !a.contains(v) { a.append(v); m[k] = a } } else { m[k] = [v] }
        }
        // syllables for input
        for (c, v) in r.syl {
            let z = v[0], l = v[1]
            push(&zyRev, z, c)
            maxZy = max(maxZy, z.unicodeScalars.count)
            if c.contains("ø") { push(&zyRev, z.replacingOccurrences(of: "ㄜ", with: "ㄛ"), c) }
            if z.hasSuffix("ˉ") { push(&zyRev0, String(z.dropLast()), c) }
            push(&latRev, l.precomposedStringWithCanonicalMapping.lowercased(), c)
        }
        for (c, v) in r.tl where v.count > 1 {
            push(&tlRev, v[1], c)
            push(&pojRev, Dict.tl2poj(v[1]), c)
            push(&plainRev, Dict.plainKey(v[1]), c)
            push(&plainRev, Dict.plainKey(Dict.tl2poj(v[1])), c)
        }
        for (c, v) in r.syl { push(&plainRev, Dict.plainKey(v[1]), c) }
        // words
        for w in r.words where w.count == 2 {
            let h = w[0], c = w[1]
            push(&hanMap, h, c); push(&codeMap, c, h)
            maxHan = max(maxHan, h.count)
            maxSyl = max(maxSyl, c.split(separator: " ").count)
        }
        maxHan = min(maxHan, 12)
        for w in r.words where w.count == 2 {
            let hs = w[0].map { String($0) }, cs = w[1].split(separator: " ").map(String.init)
            guard hs.count == cs.count else { continue }
            for (k, ch) in hs.enumerated() { pairCount[ch + "|" + cs[k], default: 0] += 1 }
        }
        for (c, list) in codeMap {
            codeMap[c] = list.sorted { score($0, c) > score($1, c) }
        }
        let rank = ["白": 0, "俗": 1, "": 2, "文": 3]
        for (h, list) in hanMap where h.count == 1 && list.count > 1 {
            hanMap[h] = list.sorted { (rank[r.reg[h + "\t" + $0] ?? ""] ?? 2) < (rank[r.reg[h + "\t" + $1] ?? ""] ?? 2) }
        }
        // other readings and dialect readings: typing them finds the word too
        for w in r.words where w.count == 2 {
            let h = w[0], c = w[1], k = h + "\t" + c
            var extra: [Opt] = []
            for a in r.alt[k] ?? [] where !a.isEmpty {
                extra.append(Opt(han: h, codes: a[0].split(separator: " ").map(String.init), parent: k,
                                 label: (a.count > 1 && !a[1].isEmpty) ? a[1] : "又", tokens: a.count > 2 ? a[2] : nil))
            }
            for (_, dc) in r.dia[k] ?? [:] where dc != c {
                altParent[h + "\t" + dc] = k
                push(&codeMap, dc, h)
            }
            for o in extra {
                let cs = o.codes!.joined(separator: " ")
                if cs == c { continue }
                altParent[h + "\t" + cs] = k
                push(&codeMap, cs, h)
                maxSyl = max(maxSyl, o.codes!.count)
                hanAlt[h, default: []].append(o)
            }
        }
        // variant characters (異用字)
        for (v, keys) in r.variants where hanMap[v] == nil {
            for k in keys {
                guard let tab = k.firstIndex(of: "\t") else { continue }
                let c = String(k[k.index(after: tab)...])
                push(&hanMap, v, c)
                altParent[v + "\t" + c] = k
                maxHan = max(maxHan, v.count)
            }
        }
        for (k, cs) in r.cat ?? [:] { for c in cs { catWords[c, default: []].append(k) } }
        // 華語 glossary
        for e in r.gl where e.count == 2 {
            let arr = e[1].split(separator: "|").map { s -> (t: String, ex: Bool) in
                s.hasPrefix("~") ? (String(s.dropFirst()), true) : (String(s), false)
            }
            gl[e[0]] = arr
            for x in arr { push(&termIndex, x.t, e[0]) }
        }
    }

    /// a romanized syllable without tone: lower case, no marks, no tone number
    static func plainKey(_ s: String) -> String {
        let t = s.lowercased().decomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "o\u{0358}", with: "oo").replacingOccurrences(of: "ⁿ", with: "nn")
        var out = ""
        for u in t.unicodeScalars where !(0x300...0x36F).contains(u.value) && !("0"..."9").contains(Character(u)) {
            out.unicodeScalars.append(u)
        }
        return out
    }

    static func tl2poj(_ s: String) -> String {
        var t = s
        if t.hasPrefix("tsh") { t = "chh" + t.dropFirst(3) } else if t.hasPrefix("ts") { t = "ch" + t.dropFirst(2) }
        t = t.replacingOccurrences(of: "ua", with: "oa").replacingOccurrences(of: "ue", with: "oe")
        if let r = t.range(of: #"ing(?=\d)"#, options: .regularExpression) { t.replaceSubrange(r, with: "eng") }
        if let r = t.range(of: #"ik(?=\d)"#, options: .regularExpression) { t.replaceSubrange(r, with: "ek") }
        return t
    }

    func charScore(_ ch: String, _ c: String) -> Double {
        log(1 + Double(pairCount[ch + "|" + c] ?? 0)) + 0.45 * (raw.freq[ch] ?? 0) + (Dict.taigiCommon.contains(ch) ? 6 : 0)
    }
    func score(_ h: String, _ c: String) -> Double {
        let hs = h.map { String($0) }, cs = c.split(separator: " ").map(String.init)
        guard hs.count == cs.count, !hs.isEmpty else { return 0 }
        return zip(hs, cs).reduce(0) { $0 + charScore($1.0, $1.1) } / Double(hs.count)
    }

    // MARK: keys

    func keyOf(_ o: Opt) -> String? {
        guard let h = o.han, let codes = o.codes else { return nil }
        if let p = o.parent { return p }
        let k = h + "\t" + codes.joined(separator: " ")
        return baseKeys.contains(k) ? k : (altParent[k] ?? k)
    }
    static func codesOf(_ key: String) -> String {
        guard let tab = key.firstIndex(of: "\t") else { return "" }
        return String(key[key.index(after: tab)...])
    }
    static func hanOf(_ key: String) -> String {
        guard let tab = key.firstIndex(of: "\t") else { return key }
        return String(key[..<tab])
    }

    // MARK: rendering (same rules as fangcore.js)

    /// sys: 0 皓羅, 1 台羅, 2 白話字, 3 方音; place: -1 = 通行
    func syl(_ c: String, _ sys: Int, _ place: Int) -> String {
        guard let s = raw.syl[c] else { return c }
        switch sys {
        case 3: return place >= 0 && c.contains("ø") ? s[0].replacingOccurrences(of: "ㄜ", with: "ㄛ") : s[0]
        case 1: return raw.tl[c]?.first ?? s[1]
        case 2: return raw.pj[c] ?? s[1]
        default: return s[1]
        }
    }
    func isCode(_ t: String) -> Bool { raw.syl[t] != nil }

    func codesFor(_ key: String, _ place: Int) -> String {
        if place >= 0, let d = raw.dia[key]?[String(place)] { return d }
        return Dict.codesOf(key)
    }

    func tokensFor(_ key: String, _ place: Int, codes: String? = nil) -> [String] {
        let cs = (codes ?? codesFor(key, place)).split(separator: " ").map(String.init)
        guard let base = raw.tok[key] else { return cs }
        var i = 0
        return base.split(separator: " ").map { t0 in
            let t = String(t0)
            let cap = t.hasPrefix("^"), c = cap ? String(t.dropFirst()) : t
            guard isCode(c) else { return t }
            let n = i < cs.count ? cs[i] : c
            i += 1
            return (cap ? "^" : "") + n
        }
    }

    func render(_ tokens: [String], _ sys: Int, _ place: Int) -> String {
        var out = "", prevCode = false
        for t in tokens {
            let cap = t.hasPrefix("^"), c = cap ? String(t.dropFirst()) : t
            if isCode(c) {
                if sys != 3 && prevCode { out += "-" }
                var s = syl(c, sys, place)
                if cap && sys != 3 { s = s.prefix(1).uppercased() + s.dropFirst() }
                out += s; prevCode = true
            } else if t == "--" { if sys != 3 { out += "--" }; prevCode = false }
            else if t == "_" { out += " "; prevCode = false }
            else if t.hasPrefix("~") { out += String(t.dropFirst()); prevCode = false }
            else { out += t; prevCode = false }
        }
        return out
    }

    func word(_ key: String, _ sys: Int, _ place: Int) -> String { render(tokensFor(key, place), sys, place) }

    /// syllables (by position) whose reading for the place is worked out by rule, not stated by the dictionary
    func guessedSyllables(_ key: String, _ place: Int) -> Set<Int> {
        guard place >= 0, !isStated(key, place), let dc = raw.dia[key]?[String(place)] else { return [] }
        let a = Dict.codesOf(key).split(separator: " "), b = dc.split(separator: " ")
        guard a.count == b.count else { return Set(0..<b.count) }
        return Set(b.indices.filter { a[$0] != b[$0] })
    }

    /// the word as (text, guessed) pieces, so guessed syllables can be coloured
    func wordPieces(_ key: String, _ sys: Int, _ place: Int) -> [(text: String, guessed: Bool)] {
        let g = guessedSyllables(key, place)
        if g.isEmpty { return [(word(key, sys, place), false)] }
        var out: [(text: String, guessed: Bool)] = []
        func put(_ t: String, _ guessed: Bool) {
            guard !t.isEmpty else { return }
            if let l = out.last, l.guessed == guessed { out[out.count - 1].text += t } else { out.append((t, guessed)) }
        }
        var prevCode = false, n = 0
        for t in tokensFor(key, place) {
            let cap = t.hasPrefix("^"), c = cap ? String(t.dropFirst()) : t
            if isCode(c) {
                if sys != 3 && prevCode { put("-", false) }
                var s = syl(c, sys, place)
                if cap && sys != 3 { s = s.prefix(1).uppercased() + s.dropFirst() }
                put(s, g.contains(n)); n += 1; prevCode = true
            } else if t == "--" { if sys != 3 { put("--", false) }; prevCode = false }
            else if t == "_" { put(" ", false); prevCode = false }
            else if t.hasPrefix("~") { put(String(t.dropFirst()), false); prevCode = false }
            else { put(t, false); prevCode = false }
        }
        return out
    }

    func codes(_ cs: String, _ sys: Int, _ place: Int, tokens: String? = nil) -> String {
        render((tokens ?? cs).split(separator: " ").map(String.init), sys, place)
    }

    /// true when MOE's 語音差異 gives this word's reading for the place (not worked out by rule)
    func isStated(_ key: String, _ place: Int) -> Bool {
        guard place >= 0, let s = raw.dex?[key] else { return false }
        return s.contains(Character(String(place)))
    }

    /// an example sentence as (text, guessed) pieces; with a place chosen, the words in it take that
    /// place's reading (the 漢字 sentence tells which syllables belong to which dictionary word).
    /// guessed = a reading the dictionary doesn't state for that word and place.
    func sentencePieces(_ tpl: String, _ sys: Int, place: Int = -1, han: String? = nil) -> [(text: String, guessed: Bool)] {
        let t = (place >= 0 && han != nil) ? dialectTemplate(han!, tpl, place) : tpl
        var out: [(text: String, guessed: Bool)] = []
        var rest = Substring(t)
        func plain(_ x: Substring) {
            guard !x.isEmpty else { return }
            if let l = out.last, !l.guessed { out[out.count - 1].text += x } else { out.append((String(x), false)) }
        }
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            plain(rest[..<open])
            var c = String(rest[rest.index(after: open)..<close])
            let cap = c.hasPrefix("^")
            if cap { c.removeFirst() }
            let guessed = c.hasPrefix("?")
            if guessed { c.removeFirst() }
            var s = isCode(c) ? syl(c, sys, place) : c
            if cap { s = s.prefix(1).uppercased() + s.dropFirst() }
            if guessed { out.append((s, true)) } else { plain(Substring(s)) }
            rest = rest[rest.index(after: close)...]
        }
        plain(rest)
        return out
    }

    func sentence(_ tpl: String, _ sys: Int, place: Int = -1, han: String? = nil) -> String {
        sentencePieces(tpl, sys, place: place, han: han).map { $0.text }.joined()
    }

    /// does this example have a guessed reading for the place?
    func hasGuess(_ tpl: String, han: String, place: Int) -> Bool {
        guard place >= 0 else { return false }
        let t = dialectTemplate(han, tpl, place)
        return t.contains("{?") || t.contains("{^?")
    }

    private var dialectCache: [String: String] = [:]
    private let cacheLock = NSLock()

    /// the template with each word's codes swapped for the place's reading, where the dictionary has one
    func dialectTemplate(_ han: String, _ tpl: String, _ place: Int) -> String {
        let ck = String(place) + "|" + tpl
        cacheLock.lock()
        if let c = dialectCache[ck] { cacheLock.unlock(); return c }
        cacheLock.unlock()
        let result = makeDialectTemplate(han, tpl, place)
        cacheLock.lock(); dialectCache[ck] = result; cacheLock.unlock()
        return result
    }

    private func makeDialectTemplate(_ han: String, _ tpl: String, _ place: Int) -> String {
        // 漢字 of the sentence, one per syllable
        let hs: [String] = han.unicodeScalars.filter { ConvertEngine.isHan($0.value) }.map { String($0) }
        // syllables of the template: (content range, code, separator before it)
        struct Tk { let range: Range<String.Index>; let code: String; let sep: Substring }
        var tks: [Tk] = []
        var i = tpl.startIndex, prevEnd = tpl.startIndex
        while let open = tpl[i...].firstIndex(of: "{"), let close = tpl[open...].firstIndex(of: "}") {
            var start = tpl.index(after: open)
            if tpl[start] == "^" { start = tpl.index(after: start) }
            tks.append(Tk(range: start..<close, code: String(tpl[start..<close]), sep: tpl[prevEnd..<open]))
            prevEnd = tpl.index(after: close)
            i = prevEnd
        }
        guard !tks.isEmpty, tks.count == hs.count else { return tpl }
        // words: syllables joined with - or --
        var groups: [[Int]] = []
        for (n, t) in tks.enumerated() {
            if n > 0, t.sep == "-" || t.sep == "--" { groups[groups.count - 1].append(n) } else { groups.append([n]) }
        }
        var rep: [Int: String] = [:]
        func key(_ seg: ArraySlice<Int>) -> String {
            seg.map { hs[$0] }.joined() + "\t" + seg.map { tks[$0].code }.joined(separator: " ")
        }
        func use(_ seg: ArraySlice<Int>, _ k: String, whole: Bool) {
            guard let dc = raw.dia[k]?[String(place)] else { return }
            let cs = dc.split(separator: " ").map(String.init)
            guard cs.count == seg.count else { return }
            // sure only when the dictionary states this word's reading for the place
            let sure = whole && isStated(k, place)
            for (j, n) in seg.enumerated() {
                rep[n] = (sure || cs[j] == tks[n].code) ? cs[j] : "?" + cs[j]
            }
        }
        for g in groups {
            // the whole word, then its parts around a light-tone --, then the longest known words from the left
            var segs: [ArraySlice<Int>] = [g[...]]
            var parts: [ArraySlice<Int>] = [], from = 0
            for (j, n) in g.enumerated() where j > 0 && tks[n].sep == "--" { parts.append(g[from..<j]); from = j }
            if !parts.isEmpty { parts.append(g[from...]); segs += parts }
            var done = false
            for seg in segs {
                let k = key(seg)
                if baseKeys.contains(k) { use(seg, k, whole: true); done = true; break }
            }
            if done { continue }
            var a = 0
            while a < g.count {
                var step = 1
                for L in stride(from: g.count - a, through: 1, by: -1) {
                    let seg = g[a..<a + L], k = key(seg)
                    if baseKeys.contains(k) { use(seg, k, whole: false); step = L; break }
                }
                a += step
            }
        }
        if rep.isEmpty { return tpl }
        var out = tpl
        for (n, t) in tks.enumerated().reversed() { if let c = rep[n] { out.replaceSubrange(t.range, with: c) } }
        return out
    }

    /// other readings: 又 / 俗 / 合, and the 通行 one when a place is shown
    func others(_ key: String, _ place: Int) -> [(label: String, codes: String, tokens: String?)] {
        var out: [(label: String, codes: String, tokens: String?)] = []
        let main = Dict.codesOf(key), shown = codesFor(key, place)
        if shown != main { out.append(("通行", main, raw.tok[key])) }
        for a in raw.alt[key] ?? [] where !a.isEmpty && a[0] != shown {
            out.append(((a.count > 1 && !a[1].isEmpty) ? a[1] : "又", a[0], a.count > 2 ? a[2] : nil))
        }
        return out
    }

    // MARK: meanings

    func senses(_ key: String) -> [DictSense] {
        guard let di = raw.defs.m[key] else { return [] }
        let pos = (raw.pos[key] ?? "").components(separatedBy: "|")
        let sy = raw.sy[key] ?? [:], an = raw.an[key] ?? [:]
        return raw.defs.t[di].components(separatedBy: "\n").enumerated().map { i, line in
            var text = line
            if let r = line.range(of: #"^\d+\.\s*"#, options: .regularExpression) { text = String(line[r.upperBound...]) }
            let exs = (raw.ex[key].flatMap { i < $0.count ? $0[i] : nil }) ?? []
            return DictSense(n: i + 1, pos: i < pos.count ? pos[i] : "", text: text, ex: exs,
                             syn: sy[String(i)] ?? [], ant: an[String(i)] ?? [])
        }
    }
    /// whole-word links that are not already shown under a meaning
    func wordLinks(_ key: String) -> (syn: [String], ant: [String]) {
        func pick(_ m: [String: [String]]?) -> [String] {
            guard let m else { return [] }
            return (m["e"] ?? []).filter { x in !m.contains { $0.key != "e" && $0.value.contains(x) } }
        }
        return (pick(raw.sy[key]), pick(raw.an[key]))
    }

    func defText(_ key: String) -> String? { raw.defs.m[key].map { raw.defs.t[$0] } }
}
