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
    let dia2: [String: [String: [String]]]?   // other ways the place says the word (粗紙 in 高雄: tshoo-tsuá, thoo-tsuá)
    let dex: [String: String]?          // places whose reading MOE states (the others are worked out by rule)

    enum CodingKeys: String, CodingKey {
        case words, syl, tl, pj, defs, pos, ex, reg, own, au, gl, freq, places, alt, dia, tok, sub, typ, sy, an, cmp, names, sur, types, cats, cat, dex, ctx, dia2
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
    /// places where 台羅 o is always said ㄜ (臺南, 高雄)
    let orPlaces: Set<Int>
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
        orPlaces = Set(r.places.indices.filter { r.places[$0].hasPrefix("臺南") || r.places[$0].hasPrefix("高雄") })

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

    // MARK: 自訂 (your own words)

    /// your own words (not in the MOE dictionary): found by 轉換 and 詞典 like any other word
    private(set) var userKeys: Set<String> = []
    func isUser(_ key: String) -> Bool { userKeys.contains(key) }

    /// the current list of your words: the ones removed leave the dictionary, new ones join it
    func setUserWords(_ keys: Set<String>) {
        let wanted = Set(keys.filter { !baseKeys.contains($0) && altParent[$0] == nil && $0.contains("\t") })
        guard wanted != userKeys else { return }
        for k in userKeys.subtracting(wanted) {
            let h = Dict.hanOf(k), c = Dict.codesOf(k)
            hanMap[h]?.removeAll { $0 == c }
            if hanMap[h]?.isEmpty == true { hanMap[h] = nil }
            codeMap[c]?.removeAll { $0 == h }
            if codeMap[c]?.isEmpty == true { codeMap[c] = nil }
        }
        for k in wanted.subtracting(userKeys) {
            let h = Dict.hanOf(k), c = Dict.codesOf(k)
            if !(hanMap[h]?.contains(c) ?? false) { hanMap[h, default: []].append(c) }
            if !(codeMap[c]?.contains(h) ?? false) { codeMap[c, default: []].append(h) }
            maxHan = max(maxHan, min(h.count, 12))
            maxSyl = max(maxSyl, c.split(separator: " ").count)
        }
        userKeys = wanted
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
        // with a place chosen, 台羅 o is ㄛ — except in 臺南 and 高雄, where o is always said ㄜ
        case 3: return place >= 0 && c.contains("ø") && !orPlaces.contains(place) ? s[0].replacingOccurrences(of: "ㄜ", with: "ㄛ") : s[0]
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

    /// a local syllable that sounds like the 通行 one. In 臺南 and 高雄 o is said "or" (ㄜ), which is how 通行 o
    /// is said too: MOE just spells it o. So there o → or is no change (the "or" spelling is still shown).
    func sameSound(_ common: String, _ local: String, _ place: Int) -> Bool {
        common == local || (orPlaces.contains(place) && common.replacingOccurrences(of: "ø", with: "ɵ") == local)
    }

    /// the place says the word differently from 通行 (not counting 臺南/高雄 o → or)
    func differsFromCommon(_ key: String, _ place: Int) -> Bool {
        guard place >= 0, let dc = raw.dia[key]?[String(place)] else { return false }
        let a = Dict.codesOf(key).split(separator: " ").map(String.init), b = dc.split(separator: " ").map(String.init)
        guard a.count == b.count else { return true }
        return b.indices.contains { !sameSound(a[$0], b[$0], place) }
    }

    /// syllables (by position) whose reading for the place is worked out by rule, not stated by the dictionary
    func guessedSyllables(_ key: String, _ place: Int) -> Set<Int> {
        guard place >= 0, !isStated(key, place), let dc = raw.dia[key]?[String(place)] else { return [] }
        let a = Dict.codesOf(key).split(separator: " ").map(String.init), b = dc.split(separator: " ").map(String.init)
        guard a.count == b.count else { return Set(0..<b.count) }
        return Set(b.indices.filter { !sameSound(a[$0], b[$0], place) })
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
        examplePieces(tpl, sys, place: place, han: han, zh: nil).map { ($0.text, $0.mark == 1) }
    }

    /// an example sentence in 羅馬字 as pieces: mark 0 = as MOE has it (or a reading MOE states for the place),
    /// 1 = guessed local reading, 2 = a word the place says differently (各地講法), swapped in.
    /// With a place: the place's own words first (localizedExample), then its readings (dialectTemplate).
    func examplePieces(_ tpl: String, _ sys: Int, place: Int = -1, han: String? = nil, zh: String? = nil) -> [(text: String, mark: Int)] {
        var t = tpl
        if place >= 0, let h = han {
            let loc = localizedExample(h, tpl, place, zh: zh)
            t = dialectTemplate(loc.han, loc.tpl, place)
        }
        var out: [(text: String, mark: Int)] = []
        var rest = Substring(t)
        func put(_ x: String, _ m: Int) {
            guard !x.isEmpty else { return }
            if let l = out.last, l.mark == m { out[out.count - 1].text += x } else { out.append((x, m)) }
        }
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            put(String(rest[..<open]), 0)
            var c = String(rest[rest.index(after: open)..<close])
            let cap = c.hasPrefix("^")
            if cap { c.removeFirst() }
            var m = 0
            if c.hasPrefix("?") { m = 1; c.removeFirst() } else if c.hasPrefix("!") { m = 2; c.removeFirst() }
            var s = isCode(c) ? syl(c, sys, place) : c
            if cap { s = s.prefix(1).uppercased() + s.dropFirst() }
            put(s, m)
            rest = rest[rest.index(after: close)...]
        }
        put(String(rest), 0)
        return out
    }

    // MARK: words each place says differently (各地講法)

    private var vocabIndex: [String: [Int]]? = nil
    private let vocabLock = NSLock()

    /// the 各地講法 index (word -> meanings it's listed for); call with vocabLock held
    private func ensureVocabIndexLocked() {
        if vocabIndex != nil { return }
        var idx: [String: [Int]] = [:]
        for (i, e) in raw.cmp.enumerated() {
            for h in Set(e.rows.map { $0.han }) { idx[h, default: []].append(i) }
        }
        vocabIndex = idx
        // 近義 links between words, by 漢字, both ways (啥物 ↔ 啥貨)
        var syn: [String: Set<String>] = [:]
        for (k, m) in raw.sy {
            let a = Dict.hanOf(k)
            for list in m.values {
                for other in list {
                    let b = Dict.hanOf(other)
                    if a != b { syn[a, default: []].insert(b); syn[b, default: []].insert(a) }
                }
            }
        }
        synHan = syn
    }
    /// 近義 by 漢字, both ways: a place's word listed as 近義 of the original means the original is a normal word too
    private var synHan: [String: Set<String>] = [:]

    /// a word of the place's own, with whether it may be swapped in by itself (auto) or only picked in 選詞
    struct VocabCandidate { let han: String; let codes: [String]; var auto: Bool }

    /// the words this place uses instead of `word`, from 詞彙比較: only when the place lists words for the
    /// meaning and `word` isn't one of them (做伙 → 金門 相佮). Empty = the place says it this way too.
    /// zh = the sentence's 華語 translation: a meaning only counts when its 華語 word is in it, so 愛 meaning
    /// 要 (你愛去 → 你要去) can become 欲, while 愛 meaning 喜歡 (我愛你) stays. No translation = no change.
    /// A candidate is only swapped in by itself (auto) when the match is trustworthy:
    ///  - the meaning's 華語 word that matched is longer than one character (是, 很, 要, 大, 頭, 家 match almost
    ///    every sentence, so they say little about this one)
    ///  - the meaning doesn't have a long list of ways to say it (6 or more words = people say it many ways, and
    ///    a word missing from the place's list probably just wasn't recorded)
    ///  - the candidate isn't the same word made longer or shorter (落雨 → 落雨天, 學校 → 公學校, 囡仔人 → 囡仔,
    ///    目睭 → 目睭仁, 莫 → 莫去): those are variants, and the original is very likely said there too
    ///  - MOE doesn't list the two as 近義 (啥物 ↔ 啥貨): then the original is a normal word in its own right
    func vocabCandidates(_ word: String, _ place: Int, zh: String?) -> [VocabCandidate] {
        guard let zh, !zh.isEmpty else { return [] }
        if sentenceCount(word) >= Dict.commonCutoff { return [] }     // a very common word: never changed, nothing to pick
        vocabLock.lock()
        ensureVocabIndexLocked()
        let concepts = vocabIndex?[word] ?? []
        let syns = synHan[word] ?? []
        vocabLock.unlock()
        var out: [VocabCandidate] = []
        for i in concepts {
            let matched = Dict.conceptTerms(raw.cmp[i].zh).filter { zh.contains($0) }
            if matched.isEmpty { continue }
            let rows = raw.cmp[i].rows.filter { $0.place == place }
            if rows.isEmpty { continue }                       // nothing known for this place
            if rows.contains(where: { $0.han == word }) { return [] }    // the place says it this way too
            let strongMeaning = matched.contains { $0.count > 1 } && Set(raw.cmp[i].rows.map { $0.han }).count < 6
            for r in rows {
                if Dict.wrongPairs.contains(word + "→" + r.han) { continue }
                let codes = r.codes.split(separator: " ").map(String.init)
                guard !codes.isEmpty, codes.count == r.han.count, codes.allSatisfy({ isCode($0) }) else { continue }
                let auto = strongMeaning && !r.han.contains(word) && !word.contains(r.han) && !syns.contains(r.han)
                if let j = out.firstIndex(where: { $0.han == r.han }) { out[j].auto = out[j].auto || auto }
                else { out.append(VocabCandidate(han: r.han, codes: codes, auto: auto)) }
            }
        }
        return out
    }

    /// pairs where the 華語 meaning matches but the words don't mean the same in a sentence: never swapped or offered
    static let wrongPairs: Set<String> = ["無夠→較無一半", "穡頭→職業", "開講→畫虎𡳞", "烏白講→臭彈"]

    /// every word the place could use instead (the 選詞 menu)
    func vocabOptions(_ word: String, _ place: Int, zh: String?) -> [(han: String, codes: [String])] {
        vocabCandidates(word, place, zh: zh).map { ($0.han, $0.codes) }
    }

    /// words used in this many example sentences or more are never swapped and can't be picked in 選詞
    /// (是, 真, 愛, 毋通, 莫, 這馬, 啥物…): they're grammar and everyday words, and 各地講法 only covers one use of them.
    static let commonCutoff = 100
    private var wordCounts: [String: Int]? = nil

    /// in how many MOE example sentences the word is used, split into words the same way as the swaps
    /// (only counted for words in 各地講法)
    func sentenceCount(_ word: String) -> Int {
        vocabLock.lock(); defer { vocabLock.unlock() }
        ensureVocabIndexLocked()
        if wordCounts == nil {
            var counts: [String: Int] = [:]
            let listed = vocabIndex ?? [:]
            for senses in raw.ex.values {
                for exs in senses {
                    for e in exs where e.count > 1 {
                        for w in Set(sentenceWords(e[0], e[1])) where listed[w] != nil { counts[w, default: 0] += 1 }
                    }
                }
            }
            wordCounts = counts
        }
        return wordCounts?[word] ?? 0
    }

    /// an example's words: the dashes join syllables; inside a group, the longest dictionary words
    private func sentenceWords(_ han: String, _ tpl: String) -> [String] {
        let chars = Array(han)
        let hanIdx = chars.indices.filter { chars[$0].unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false }
        var codes: [String] = [], seps: [Substring] = []
        var i = tpl.startIndex, prevEnd = tpl.startIndex
        while let open = tpl[i...].firstIndex(of: "{"), let close = tpl[open...].firstIndex(of: "}") {
            var start = tpl.index(after: open)
            if start < close && tpl[start] == "^" { start = tpl.index(after: start) }
            codes.append(String(tpl[start..<close])); seps.append(tpl[prevEnd..<open])
            prevEnd = tpl.index(after: close); i = prevEnd
        }
        guard !codes.isEmpty, codes.count == hanIdx.count else { return [] }
        var groups: [[Int]] = []
        for n in codes.indices {
            if n > 0, seps[n] == "-" || seps[n] == "--" { groups[groups.count - 1].append(n) } else { groups.append([n]) }
        }
        var out: [String] = []
        for g in groups {
            var a = 0
            while a < g.count {
                var step = 1
                for L in stride(from: g.count - a, through: 1, by: -1) {
                    let seg = g[a..<a + L]
                    let w = seg.map { String(chars[hanIdx[$0]]) }.joined()
                    let k = w + "\t" + seg.map { codes[$0] }.joined(separator: " ")
                    if baseKeys.contains(k) || altParent[k] != nil { out.append(w); step = L; break }
                }
                a += step
            }
        }
        return out
    }

    /// a 各地講法 meaning's 華語 words: notes in brackets dropped, alternatives split
    /// ("土缸、醃缸" → 土缸, 醃缸; "父親(面稱)" → 父親)
    static func conceptTerms(_ zh: String) -> [String] {
        let t = zh.replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
        return t.split(whereSeparator: { "、，, ".contains($0) }).map { String($0) }.filter { !$0.isEmpty }
    }

    /// your choices in the word picker: "place|original word" -> chosen word (the original = keep it)
    private var choiceCache: (raw: String, map: [String: String]) = ("", [:])
    func swapChoices() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: "ff-swaps") ?? ""
        vocabLock.lock(); defer { vocabLock.unlock() }
        if raw != choiceCache.raw {
            let m = (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
            choiceCache = (raw, m)
        }
        return choiceCache.map
    }

    /// sentences whose 在地詞 switch is off ("place|sentence 漢字"): they keep their original words
    private var offCache: (raw: String, set: Set<String>) = ("", [])
    func swapsOff() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: "ff-swap-off") ?? ""
        vocabLock.lock(); defer { vocabLock.unlock() }
        if raw != offCache.raw {
            offCache = (raw, Set((try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []))
        }
        return offCache.set
    }
    static func swapOffKey(_ han: String, _ place: Int) -> String { "\(place)|\(han)" }

    /// the word to show instead of `word` for this place (nil = keep `word`): your choice in 選詞; else the place's
    /// first word whose match is trustworthy (see vocabCandidates; very common words have no candidates at all)
    func vocabSwap(_ word: String, _ place: Int, zh: String?) -> (han: String, codes: [String])? {
        let cands = vocabCandidates(word, place, zh: zh)
        guard !cands.isEmpty else { return nil }
        if let c = swapChoices()["\(place)|\(word)"] {
            if c == word { return nil }
            if let o = cands.first(where: { $0.han == c }) { return (o.han, o.codes) }
        }
        return cands.first(where: { $0.auto }).map { ($0.han, $0.codes) }
    }

    /// the example with the words the place says differently swapped in: new 漢字, new template (swapped
    /// syllables written {!code}), and the positions of the swapped 漢字 in the new sentence
    func localizedExample(_ han: String, _ tpl: String, _ place: Int, zh: String?) -> (han: String, tpl: String, swapped: Set<Int>, words: [Int: String]) {
        let chars = Array(han)
        let hanIdx = chars.indices.filter { chars[$0].unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false }
        struct Tk { let range: Range<String.Index>; let code: String; let cap: Bool; let sep: Range<String.Index> }
        var tks: [Tk] = []
        var i = tpl.startIndex, prevEnd = tpl.startIndex
        while let open = tpl[i...].firstIndex(of: "{"), let close = tpl[open...].firstIndex(of: "}") {
            var start = tpl.index(after: open)
            let cap = start < close && tpl[start] == "^"
            if cap { start = tpl.index(after: start) }
            tks.append(Tk(range: open..<tpl.index(after: close), code: String(tpl[start..<close]), cap: cap, sep: prevEnd..<open))
            prevEnd = tpl.index(after: close)
            i = prevEnd
        }
        guard !tks.isEmpty, tks.count == hanIdx.count else { return (han, tpl, [], [:]) }
        let off = swapsOff().contains(Dict.swapOffKey(han, place))     // the sentence's 在地詞 switch is off
        // words: the dashes join syllables; inside a group, the longest dictionary words
        var groups: [[Int]] = []
        for (n, t) in tks.enumerated() {
            let sep = tpl[t.sep]
            if n > 0, sep == "-" || sep == "--" { groups[groups.count - 1].append(n) } else { groups.append([n]) }
        }
        var origin: [Int: String] = [:]
        var swaps: [Int: (len: Int, han: String, codes: [String])] = [:]     // first syllable -> replacement
        var kept: [Int: (len: Int, word: String)] = [:]                       // words with choices, kept as they are
        for g in groups {
            var a = 0
            while a < g.count {
                var step = 1
                for L in stride(from: g.count - a, through: 1, by: -1) {
                    let seg = g[a..<a + L]
                    let w = seg.map { String(chars[hanIdx[$0]]) }.joined()
                    let k = w + "\t" + seg.map { tks[$0].code }.joined(separator: " ")
                    if baseKeys.contains(k) || altParent[k] != nil {
                        if !off, let r = vocabSwap(w, place, zh: zh) { swaps[seg.first!] = (L, r.han, r.codes); origin[seg.first!] = w }
                        else if !vocabOptions(w, place, zh: zh).isEmpty { kept[seg.first!] = (L, w) }
                        step = L; break
                    }
                }
                a += step
            }
        }
        if swaps.isEmpty && kept.isEmpty { return (han, tpl, [], [:]) }
        // new template
        var outT = "", n = 0
        while n < tks.count {
            outT += tpl[tks[n].sep]
            if let s = swaps[n] {
                outT += s.codes.enumerated().map { j, c in "{" + (j == 0 && tks[n].cap ? "^" : "") + "!" + c + "}" }.joined(separator: "-")
                n += s.len
            } else {
                outT += tpl[tks[n].range]
                n += 1
            }
        }
        outT += tpl[tks[tks.count - 1].range.upperBound...]
        // new 漢字
        var outH: [Character] = [], swapped = Set<Int>(), skip = Set<Int>(), words: [Int: String] = [:]
        let pos = Dictionary(uniqueKeysWithValues: hanIdx.enumerated().map { ($1, $0) })   // char index -> syllable
        for (ci, ch) in chars.enumerated() {
            if skip.contains(ci) { continue }
            if let syl = pos[ci], let k = kept[syl] {
                for j in 0..<k.len where syl + j < hanIdx.count { words[outH.count] = k.word; outH.append(chars[hanIdx[syl + j]]); if j > 0 { skip.insert(hanIdx[syl + j]) } }
                continue
            }
            if let syl = pos[ci], let s = swaps[syl] {
                for c in s.han { swapped.insert(outH.count); words[outH.count] = origin[syl] ?? ""; outH.append(c) }
                for j in 1..<max(s.len, 1) where syl + j < hanIdx.count { skip.insert(hanIdx[syl + j]) }
                continue
            }
            outH.append(ch)
        }
        return (String(outH), outT, swapped, words)
    }

    func sentence(_ tpl: String, _ sys: Int, place: Int = -1, han: String? = nil) -> String {
        sentencePieces(tpl, sys, place: place, han: han).map { $0.text }.joined()
    }

    /// an example sentence's 漢字 split into words: (text, dictionary key or nil). The template's dashes tell
    /// which syllables make one word; a word that isn't in the dictionary is split into the longest words it has.
    func exampleWords(_ han: String, _ tpl: String) -> [(text: String, key: String?)] {
        let codes = tpl.matches(of: #/\{\^?([^}]*)\}/#).map { String($0.1) }
        var seps: [Substring] = []
        var prev = tpl.startIndex
        for m in tpl.matches(of: #/\{[^}]*\}/#) { seps.append(tpl[prev..<m.range.lowerBound]); prev = m.range.upperBound }
        let chars = Array(han)
        let hanIdx = chars.indices.filter { chars[$0].unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false }
        guard !codes.isEmpty, codes.count == hanIdx.count else { return [(han, nil)] }
        // syllable n -> key of the word it belongs to
        var keyOf = [String?](repeating: nil, count: codes.count)
        var groups: [[Int]] = []
        for n in codes.indices {
            if n > 0, seps[n] == "-" || seps[n] == "--" { groups[groups.count - 1].append(n) } else { groups.append([n]) }
        }
        func key(_ seg: ArraySlice<Int>) -> String {
            seg.map { String(chars[hanIdx[$0]]) }.joined() + "\t" + seg.map { codes[$0] }.joined(separator: " ")
        }
        func found(_ k: String) -> String? { baseKeys.contains(k) ? k : altParent[k] }
        for g in groups {
            var a = 0
            while a < g.count {
                var step = 1
                for L in stride(from: g.count - a, through: 1, by: -1) {
                    if let k = found(key(g[a..<a + L])) {
                        for n in g[a..<a + L] { keyOf[n] = k }
                        step = L; break
                    }
                }
                a += step
            }
        }
        // pieces over the whole 漢字 sentence (punctuation stays plain)
        var out: [(text: String, key: String?)] = []
        var n = 0, lastGroup = -1
        var groupOf = [Int](repeating: 0, count: codes.count)
        for (gi, g) in groups.enumerated() { for x in g { groupOf[x] = gi } }
        for (i, ch) in chars.enumerated() {
            if n < hanIdx.count, hanIdx[n] == i {
                let k = keyOf[n]
                if let last = out.last, last.key == k, k != nil, groupOf[n] == lastGroup {
                    out[out.count - 1].text.append(ch)
                } else {
                    out.append((String(ch), k))
                }
                lastGroup = groupOf[n]
                n += 1
            } else {
                if let last = out.last, last.key == nil { out[out.count - 1].text.append(ch) } else { out.append((String(ch), nil)) }
                lastGroup = -1
            }
        }
        return out
    }

    /// the template with syllables lower..<upper (by position) replaced by ＿＿ (for 例句填空)
    static func blanked(_ tpl: String, _ r: Range<Int>) -> String {
        var spans: [Range<String.Index>] = []
        var i = tpl.startIndex
        while let open = tpl[i...].firstIndex(of: "{"), let close = tpl[open...].firstIndex(of: "}") {
            spans.append(open..<tpl.index(after: close))
            i = tpl.index(after: close)
        }
        guard r.lowerBound >= 0, r.upperBound <= spans.count, !r.isEmpty else { return tpl }
        var out = tpl
        out.replaceSubrange(spans[r.lowerBound].lowerBound..<spans[r.upperBound - 1].upperBound, with: "＿＿")
        return out
    }

    /// 例句填空 sentence in 羅馬字 for a place: the word's syllables blanked out, the rest in local readings
    func blankSentencePieces(_ tpl: String, han: String, word codes: [String], _ sys: Int, place: Int) -> [(text: String, guessed: Bool)]? {
        let base = tpl.matches(of: #/\{\^?([^}]*)\}/#).map { String($0.1) }
        guard !codes.isEmpty, base.count >= codes.count,
              let at = (0...(base.count - codes.count)).first(where: { Array(base[$0..<$0 + codes.count]) == codes }) else { return nil }
        let t = place >= 0 ? dialectTemplate(han, tpl, place) : tpl
        return sentencePieces(Dict.blanked(t, at..<at + codes.count), sys, place: place)
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
                rep[n] = (sure || sameSound(tks[n].code, cs[j], place)) ? cs[j] : "?" + cs[j]
            }
        }
        for g in groups {
            // the whole word; else each part around a light-tone -- (入選--無 → 入選, 無), each as a word
            // or as the longest known words inside it
            if baseKeys.contains(key(g[...])) { use(g[...], key(g[...]), whole: true); continue }
            var parts: [ArraySlice<Int>] = [], from = 0
            for (j, n) in g.enumerated() where j > 0 && tks[n].sep == "--" { parts.append(g[from..<j]); from = j }
            parts.append(g[from...])
            for part in parts {
                if baseKeys.contains(key(part)) { use(part, key(part), whole: true); continue }
                var a = part.startIndex
                while a < part.endIndex {
                    var step = 1
                    for L in stride(from: part.endIndex - a, through: 1, by: -1) {
                        let seg = part[a..<a + L], k = key(seg)
                        if baseKeys.contains(k) { use(seg, k, whole: false); step = L; break }
                    }
                    a += step
                }
            }
        }
        if rep.isEmpty { return tpl }
        var out = tpl
        for (n, t) in tks.enumerated().reversed() { if let c = rep[n] { out.replaceSubrange(t.range, with: c) } }
        return out
    }

    /// other readings: 又 / 俗 / 合, and the 通行 one when a place is shown
    /// the place's other way(s) of saying the word, as codes
    func alsoSaid(_ key: String, _ place: Int) -> [String] {
        guard place >= 0 else { return [] }
        return raw.dia2?[key]?[String(place)] ?? []
    }

    func others(_ key: String, _ place: Int) -> [(label: String, codes: String, tokens: String?)] {
        var out: [(label: String, codes: String, tokens: String?)] = []
        let main = Dict.codesOf(key), shown = codesFor(key, place)
        for x in alsoSaid(key, place) where x != shown { out.append(("也講", x, nil)) }
        if differsFromCommon(key, place), !alsoSaid(key, place).contains(main) { out.append(("通行", main, raw.tok[key])) }
        for a in raw.alt[key] ?? [] where !a.isEmpty && a[0] != shown {
            out.append(((a.count > 1 && !a[1].isEmpty) ? a[1] : "又", a[0], a.count > 2 ? a[2] : nil))
        }
        return out
    }

    // MARK: sentences with a word (查詞 → 台語句子裡有「…」)

    /// an example sentence that uses a word: [漢字, template, 華語, audio], and the entry it's listed under
    struct SentenceHit: Sendable, Hashable { let ex: [String]; let entry: String; let word: String }
    private var sentenceIndex: [String: [(ex: [String], entry: String)]]? = nil
    private let sentenceLock = NSLock()

    /// every example sentence in the dictionary that uses one of these words (same characters and reading,
    /// found the same way as the tappable words in example sentences), shortest first
    func sentences(with keys: [String], limit: Int = 300) -> [SentenceHit] {
        guard !keys.isEmpty else { return [] }
        sentenceLock.lock()
        if sentenceIndex == nil {
            var idx: [String: [(ex: [String], entry: String)]] = [:]
            for (entry, senses) in raw.ex {
                for exs in senses {
                    for e in exs where e.count > 1 {
                        var seen = Set<String>()
                        for p in exampleWords(e[0], e[1]) {
                            if let k = p.key, seen.insert(k).inserted { idx[k, default: []].append((e, entry)) }
                        }
                    }
                }
            }
            sentenceIndex = idx
        }
        let idx = sentenceIndex ?? [:]
        sentenceLock.unlock()
        var out: [SentenceHit] = [], seenHan = Set<String>()
        for k in keys {
            for h in idx[k] ?? [] where seenHan.insert(h.ex[0]).inserted { out.append(SentenceHit(ex: h.ex, entry: h.entry, word: k)) }
        }
        return Array(out.sorted { $0.ex[0].count < $1.ex[0].count }.prefix(limit))
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
