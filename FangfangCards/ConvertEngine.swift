import Foundation

// Port of the 方方 website converter: reads 漢字 / 皓羅 / 方音 / 台羅 / 白話字 (mixed),
// splits it into dictionary words and writes it in the three scripts.

struct ConvItem {
    var opts: [Opt] = []
    var sel = 0
    var src = ""                 // han / zy / lat / tl / poj
    var raw: String? = nil       // punctuation or text that isn't a word
    var space = false
    var newline = false
    var unknownWord = false      // Latin text we couldn't read
    var isWord: Bool { raw == nil && !space && !newline }
    var current: Opt { opts[min(sel, opts.count - 1)] }
}

enum LatinMode: String, CaseIterable { case auto, lat, tl, poj }

struct ConvResult {
    var items: [ConvItem] = []
    var seen: [String: Int] = [:]
    var anyLatin = false
    var autoLatin = "lat"
}

private enum Atom {
    case han(String)
    case syl([String], String)      // codes, from
    case latin(String)              // raw Latin word
    case newline
    case space
    case raw(String)
}

final class ConvertEngine {
    let d: Dict
    var latinMode: LatinMode = .auto
    private var mem: [String: String]

    init(dict: Dict) {
        d = dict
        mem = (UserDefaults.standard.dictionary(forKey: "ff-picks") as? [String: String]) ?? [:]
        if let m = UserDefaults.standard.string(forKey: "ff-latin"), let l = LatinMode(rawValue: m) { latinMode = l }
    }

    // MARK: character classes

    static func isHan(_ v: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) ||
        (0x20000...0x3134F).contains(v) || v == 0x3007
    }
    static let zyExtra: Set<UInt32> = [0x02C9, 0x02CA, 0x02CB, 0x02EA, 0x02EB, 0x02D9, 0xFF0E, 0xFF4E, 0x0307, 0xA715, 0xA718]
    static func isZy(_ v: UInt32) -> Bool { (0x3100...0x312F).contains(v) || (0x31A0...0x31BF).contains(v) || zyExtra.contains(v) }
    static func isLatinLetter(_ v: UInt32) -> Bool {
        (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v) && v != 0xD7 && v != 0xF7 ||
        (0x1E00...0x1EFF).contains(v)
    }
    static func isMark(_ v: UInt32) -> Bool { (0x300...0x36F).contains(v) || v == 0x207F }

    // MARK: 方音 input

    private static let nas: [String: String] = ["ㄧ": "ㆪ", "ㄨ": "ㆫ", "ㄚ": "ㆩ", "ㆦ": "ㆧ", "ㆤ": "ㆥ", "ㄞ": "ㆮ", "ㄠ": "ㆯ"]
    private static func normZy(_ s: String) -> [Unicode.Scalar] {
        let stops: Set<String> = ["ㆴ", "ㆵ", "ㆻ", "ㆷ"]
        var a = Array(s.unicodeScalars), out: [Unicode.Scalar] = []
        var i = 0
        while i < a.count {
            let c = String(a[i]), nxt = i + 1 < a.count ? String(a[i + 1]) : ""
            if stops.contains(c) && (nxt == "˙" || nxt == "·") { out.append(a[i]); out.append("\u{0307}"); i += 2; continue }
            if stops.contains(c) && nxt == "．" { out.append(a[i]); i += 2; continue }
            if c == "ㆡ" && (nxt == "ㄧ" || nxt == "ㆪ") { out.append("ㆢ"); i += 1; continue }
            if let n = nas[c], nxt == c || nxt == "ｎ" { out.append(contentsOf: n.unicodeScalars); i += 2; continue }
            out.append(a[i]); i += 1
        }
        var t = String(String.UnicodeScalarView(out))
        for (x, y) in [("ㄚㆬ", "ㆰ"), ("ㆦㆬ", "ㆱ"), ("ㄚㄣ", "ㄢ"), ("ㄚㆭ", "ㄤ"), ("ㆦㆭ", "ㆲ"), ("ㄜㆭ", "ㄥ")] {
            t = t.replacingOccurrences(of: x, with: y)
        }
        a = Array(t.unicodeScalars)
        return a
    }
    private func parseZy(_ raw: String) -> [Atom] {
        let s = ConvertEngine.normZy(raw), n = s.count
        struct Step { var cost: Double; var from: Int; var atom: Atom? }
        var best = [Step?](repeating: nil, count: n + 1)
        best[0] = Step(cost: 0, from: 0, atom: nil)
        func relax(_ j: Int, _ cost: Double, _ from: Int, _ atom: Atom) {
            if best[j] == nil || cost < best[j]!.cost { best[j] = Step(cost: cost, from: from, atom: atom) }
        }
        for i in 0..<n {
            guard let b = best[i] else { continue }
            if i < n {
                for L in 1...min(d.maxZy, n - i) {
                    let k = String(String.UnicodeScalarView(s[i..<i + L]))
                    if let c = d.zyRev[k] { relax(i + L, b.cost + 1, i, .syl(c, "zy")) }
                    else if let c = d.zyRev0[k] { relax(i + L, b.cost + 1.4, i, .syl(c, "zy")) }
                }
            }
            relax(i + 1, b.cost + 10, i, .raw(String(s[i])))
        }
        var out: [Atom] = []
        var j = n
        while j > 0, let b = best[j] { if let a = b.atom { out.append(a) }; j = b.from }
        out.reverse()
        // merge neighbouring unknown characters
        var merged: [Atom] = []
        for a in out {
            if case .raw(let t) = a, case .raw(let p)? = merged.last { merged[merged.count - 1] = .raw(p + t) } else { merged.append(a) }
        }
        return merged
    }

    // MARK: Latin input

    private static let toneMark: [UInt32: String] = [0x301: "2", 0x300: "3", 0x302: "5", 0x30C: "6", 0x304: "7", 0x30D: "8", 0x30B: "9"]
    static func romKey(_ word: String) -> String? {
        var s = word.decomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "o\u{0358}", with: "oo").replacingOccurrences(of: "\u{0358}", with: "")
            .replacingOccurrences(of: "ⁿ", with: "nn")
        var tone = ""
        var letters = ""
        for u in s.unicodeScalars {
            if (0x300...0x36F).contains(u.value) { if let t = toneMark[u.value] { tone = t } } else { letters.unicodeScalars.append(u) }
        }
        s = letters
        if let last = s.last, let dgt = last.wholeNumberValue, (1...9).contains(dgt) { tone = String(dgt); s.removeLast() }
        guard !s.isEmpty, s.allSatisfy({ ("a"..."z").contains($0) }) else { return nil }
        if tone.isEmpty { tone = (s.last.map { "ptkh".contains($0) } ?? false) ? "4" : "1" }
        return s + tone
    }

    // MARK: splitting the text into atoms

    private func atomize(_ text: String, into res: inout ConvResult) -> [Atom] {
        let u = Array(text.precomposedStringWithCanonicalMapping.unicodeScalars)
        var atoms: [Atom] = []
        var i = 0
        func str(_ a: Int, _ b: Int) -> String { String(String.UnicodeScalarView(u[a..<b])) }
        while i < u.count {
            let v = u[i].value
            if ConvertEngine.isHan(v) { atoms.append(.han(String(u[i]))); i += 1; continue }
            if ConvertEngine.isZy(v) && v != 0x0307 {
                var j = i; while j < u.count && ConvertEngine.isZy(u[j].value) { j += 1 }
                atoms.append(contentsOf: parseZy(str(i, j))); i = j; continue
            }
            if ConvertEngine.isLatinLetter(v) || ConvertEngine.isMark(v) {
                var j = i
                while j < u.count && (ConvertEngine.isLatinLetter(u[j].value) || ConvertEngine.isMark(u[j].value)) { j += 1 }
                if j < u.count, (0x31...0x39).contains(u[j].value) { j += 1 }
                atoms.append(.latin(str(i, j))); i = j; continue
            }
            if v == 0x0A { atoms.append(.newline); i += 1; continue }
            if v == 0x20 || v == 0x09 || v == 0x3000 {
                var j = i; while j < u.count && (u[j].value == 0x20 || u[j].value == 0x09 || u[j].value == 0x3000) { j += 1 }
                atoms.append(.space); i = j; continue
            }
            if v == 0x2D || v == 0x2011 { atoms.append(.space); i += 1; continue }
            atoms.append(.raw(String(u[i]))); i += 1
        }
        // Latin words: 皓羅, 台羅 or 白話字. Auto mode votes with spellings only one system has.
        func look(_ sys: String, _ w: String, _ rk: String?) -> [String]? {
            switch sys {
            case "lat": return d.latRev[w.lowercased()]
            case "tl": return (rk != nil && !w.contains("ⁿ") && !w.contains("\u{0358}")) ? d.tlRev[rk!] : nil
            default: return rk.flatMap { d.pojRev[$0] }
            }
        }
        var votes = ["lat": 0.0, "tl": 0.0, "poj": 0.0]
        for a in atoms {
            if case .latin(let w) = a {
                res.anyLatin = true
                let rk = ConvertEngine.romKey(w)
                let hits = ["lat", "tl", "poj"].filter { look($0, w, rk) != nil }
                for k in hits { votes[k, default: 0] += 1.0 / Double(hits.count) }
            }
        }
        var auto = "lat"
        for k in ["tl", "poj"] where votes[k]! > votes[auto]! + 1e-6 { auto = k }
        res.autoLatin = auto
        let used = latinMode == .auto ? auto : latinMode.rawValue
        let order = [used] + ["lat", "tl", "poj"].filter { $0 != used }
        return atoms.map { (a: Atom) -> Atom in
            guard case .latin(let w) = a else { return a }
            let rk = ConvertEngine.romKey(w)
            for k in order { if let c = look(k, w, rk) { return .syl(c, k) } }
            return .raw("\u{1}" + w)                      // marked: an unreadable Latin word
        }
    }

    // MARK: words

    private func segHan(_ chars: [String]) -> [ConvItem] {
        let n = chars.count
        struct Step { var cost: Double; var from: Int; var w: String; var known: Bool }
        var best = [Step?](repeating: nil, count: n + 1)
        best[0] = Step(cost: 0, from: 0, w: "", known: false)
        for i in 0..<n {
            guard let b = best[i] else { continue }
            for L in stride(from: min(d.maxHan, n - i), through: 1, by: -1) {
                let w = chars[i..<i + L].joined()
                let known = d.hanMap[w] != nil
                if !known && L > 1 { continue }
                let cost = b.cost + (known ? 1 : 1.5)
                if best[i + L] == nil || cost < best[i + L]!.cost { best[i + L] = Step(cost: cost, from: i, w: w, known: known) }
            }
        }
        var items: [ConvItem] = []
        var j = n
        while j > 0, let b = best[j] {
            var opts: [Opt]
            if b.known {
                opts = d.hanMap[b.w]!.map { Opt(han: b.w, codes: $0.split(separator: " ").map(String.init)) }
                opts += d.hanAlt[b.w] ?? []
            } else {
                opts = [Opt(han: b.w, codes: nil)]
            }
            items.append(ConvItem(opts: opts, src: "han"))
            j = b.from
        }
        return items.reversed()
    }

    private func combos(_ lists: [[String]], cap: Int = 32) -> [[String]] {
        var acc: [[String]] = [[]]
        for l in lists {
            var next: [[String]] = []
            outer: for a in acc {
                for x in l { next.append(a + [x]); if next.count >= cap { break outer } }
            }
            acc = next
        }
        return acc
    }

    private func segSyl(_ syls: [([String], String)]) -> [ConvItem] {
        let n = syls.count
        struct Step { var cost: Double; var from: Int; var opts: [Opt] }
        var best = [Step?](repeating: nil, count: n + 1)
        best[0] = Step(cost: 0, from: 0, opts: [])
        for i in 0..<n {
            guard let b = best[i] else { continue }
            for L in 1...min(d.maxSyl, n - i) {
                var opts: [Opt] = []
                for combo in combos(syls[i..<i + L].map { $0.0 }) {
                    for h in d.codeMap[combo.joined(separator: " ")] ?? [] { opts.append(Opt(han: h, codes: combo)) }
                }
                var cost: Double
                if !opts.isEmpty { cost = b.cost + 1 }
                else if L == 1 { opts = syls[i].0.map { Opt(han: nil, codes: [$0]) }; cost = b.cost + 1.5 }
                else { continue }
                if best[i + L] == nil || cost < best[i + L]!.cost { best[i + L] = Step(cost: cost, from: i, opts: opts) }
            }
        }
        var items: [ConvItem] = []
        var j = n
        while j > 0, let b = best[j] { items.append(ConvItem(opts: b.opts, src: syls.first?.1 ?? "lat")); j = b.from }
        return items.reversed()
    }

    func convert(_ text: String) -> ConvResult {
        var res = ConvResult()
        let atoms = atomize(text, into: &res)
        var i = 0
        while i < atoms.count {
            switch atoms[i] {
            case .han:
                var chars: [String] = []
                while i < atoms.count, case .han(let c) = atoms[i] { chars.append(c); i += 1 }
                res.seen["han", default: 0] += chars.count
                res.items += segHan(chars)
            case .syl:
                var syls: [([String], String)] = []
                while i < atoms.count {
                    if case .syl(let c, let from) = atoms[i] { syls.append((c, from)); res.seen[from, default: 0] += 1; i += 1 }
                    else if case .space = atoms[i], i + 1 < atoms.count, case .syl = atoms[i + 1] { i += 1 }
                    else { break }
                }
                res.items += segSyl(syls)
            case .space: res.items.append(ConvItem(space: true)); i += 1
            case .newline: res.items.append(ConvItem(newline: true)); i += 1
            case .raw(let t):
                if t.hasPrefix("\u{1}") { res.items.append(ConvItem(raw: String(t.dropFirst()), unknownWord: true)) }
                else { res.items.append(ConvItem(raw: t)) }
                i += 1
            case .latin(let w): res.items.append(ConvItem(raw: w, unknownWord: true)); i += 1
            }
        }
        // which reading: the neighbours first (from the dictionary's example sentences), then your earlier
        // choice for this word, then how common each reading is in the examples
        for k in res.items.indices where res.items[k].opts.count > 1 {
            // what you picked before for this word between the same neighbours always wins
            if let want = mem[ctxMemKey(res.items, k)],
               let at = res.items[k].opts.firstIndex(where: { optID($0) == want }) {
                res.items[k].sel = at; continue
            }
            let guess = contextPick(res.items, k)
            if let g = guess, g.strong { res.items[k].sel = g.index; continue }
            if let want = mem[memKey(res.items[k])],
               let at = res.items[k].opts.firstIndex(where: { optID($0) == want }) {
                res.items[k].sel = at; continue
            }
            if let g = guess { res.items[k].sel = g.index }
        }
        return res
    }

    /// the 漢字 next to item k (skipping spaces and punctuation, stopping at a new line)
    private func neighbour(_ items: [ConvItem], _ k: Int, _ step: Int) -> String? {
        var j = k + step
        while j >= 0 && j < items.count {
            let it = items[j]
            if it.newline { return nil }
            if it.isWord, let h = it.current.han, it.current.codes != nil {
                return step < 0 ? h.last.map(String.init) : h.first.map(String.init)
            }
            j += step
        }
        return nil
    }

    /// best reading of a one-character word from its neighbours; strong = the neighbours themselves decided it
    private func contextPick(_ items: [ConvItem], _ k: Int) -> (index: Int, strong: Bool)? {
        guard let ctx = d.raw.ctx, items[k].src == "han", let h = items[k].opts.first?.han, h.count == 1 else { return nil }
        let prev = neighbour(items, k, -1), next = neighbour(items, k, 1)
        var best: (index: Int, score: Double, near: Int)? = nil
        for (j, o) in items[k].opts.enumerated() {
            guard let cs = o.codes, cs.count == 1, o.han == h else { continue }
            let c = cs[0]
            let l = prev.flatMap { ctx.l[$0 + "\t" + h + "\t" + c] } ?? 0
            let r = next.flatMap { ctx.r[h + "\t" + c + "\t" + $0] } ?? 0
            let u = ctx.u[h + "\t" + c] ?? 0
            let score = 2 * Double(l + r) + 0.05 * Double(u)
            if score > 0, best == nil || score > best!.score { best = (j, score, l + r) }
        }
        guard let b = best else { return nil }
        return (b.index, b.near > 0)
    }

    // MARK: remembered picks

    private func optID(_ o: Opt) -> String { (o.han ?? "") + "|" + (o.codes ?? []).joined(separator: " ") }
    private func memKey(_ it: ConvItem) -> String {
        it.src == "han" ? "h:" + (it.opts[0].han ?? "") : "c:" + (it.opts[0].codes ?? []).joined(separator: " ") + ":" + String(it.opts.count)
    }
    /// your choice for item k: remembered for this word, and for this word between these neighbours
    func remember(_ items: [ConvItem], _ k: Int) {
        let it = items[k]
        mem[memKey(it)] = optID(it.current)
        mem[ctxMemKey(items, k)] = optID(it.current)
        UserDefaults.standard.set(mem, forKey: "ff-picks")
    }

    private func ctxMemKey(_ items: [ConvItem], _ k: Int) -> String {
        "x:" + (neighbour(items, k, -1) ?? "") + "|" + memKey(items[k]) + "|" + (neighbour(items, k, 1) ?? "")
    }

    // MARK: writing the result

    /// text of one word in a mode: 0 漢字, 1 romanization (rom = 0/1/2), 2 方音
    func wordText(_ o: Opt, mode: Int, rom: Int, place: Int) -> String {
        if mode == 0 { return o.han ?? d.codes((o.codes ?? []).joined(separator: " "), rom, place) }
        guard let codes = o.codes else { return o.han ?? "" }
        let sys = mode == 2 ? 3 : rom
        if let h = o.han, o.parent == nil {
            let k = h + "\t" + codes.joined(separator: " ")
            if d.baseKeys.contains(k) { return d.word(k, sys, place) }
        }
        return d.codes(codes.joined(separator: " "), sys, place, tokens: o.tokens)
    }

    /// like wordText, split so guessed place readings can be coloured
    func wordPieces(_ o: Opt, mode: Int, rom: Int, place: Int) -> [(text: String, guessed: Bool)] {
        if mode != 0, place >= 0, let h = o.han, let codes = o.codes, o.parent == nil {
            let k = h + "\t" + codes.joined(separator: " ")
            if d.baseKeys.contains(k) { return d.wordPieces(k, mode == 2 ? 3 : rom, place) }
        }
        return [(wordText(o, mode: mode, rom: rom, place: place), false)]
    }

    static let toASCII: [String: String] = ["，": ",", "。": ".", "！": "!", "？": "?", "；": ";", "：": ":", "、": ",", "「": "“", "」": "”", "『": "‘", "』": "’", "（": "(", "）": ")"]
    static let toFull: [String: String] = [",": "，", ".": "。", "!": "！", "?": "？", ";": "；", ":": "：", "(": "（", ")": "）"]
    static let openers: Set<String> = ["“", "‘", "(", "（", "「", "『", "["]

    static func isPunct(_ t: String) -> Bool {
        guard t.unicodeScalars.count == 1, let u = t.unicodeScalars.first else { return false }
        switch u.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
             .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: return true
        default: return false
        }
    }

    /// pieces of the output for one mode: (text, index of the word item or nil)
    func pieces(_ items: [ConvItem], mode: Int, rom: Int, place: Int) -> [(text: String, item: Int?)] {
        var out: [(text: String, item: Int?)] = []
        var prev: Character? = nil          // w word, x foreign text, o opening punct, p other punct
        var lastText = ""
        for (idx, it) in items.enumerated() {
            if it.newline { out.append(("\n", nil)); prev = nil; lastText = "\n"; continue }
            if it.space { continue }
            if let raw = it.raw {
                var t = raw, kind: Character
                if ConvertEngine.isPunct(t) && !it.unknownWord {
                    t = mode == 1 ? (ConvertEngine.toASCII[t] ?? t) : (ConvertEngine.toFull[t] ?? t)
                    kind = ConvertEngine.openers.contains(t) ? "o" : "p"
                } else { kind = "x" }
                var space = false
                if let p = prev, p != "o" {
                    space = kind == "x" ? (p != "p" || mode == 1) : (kind == "o" ? mode == 1 : false)
                }
                if !space, kind == "x", prev == "p", mode != 1, let l = lastText.last, ",.!?;:".contains(l) { space = true }
                out.append(((space ? " " : "") + t, it.unknownWord ? -1 : nil))
                prev = kind; lastText = t
                continue
            }
            var space = false
            if prev == "w" || prev == "x" { space = mode != 0 || prev == "x" }
            else if prev == "p" { space = mode == 1 }
            let t = wordText(it.current, mode: mode, rom: rom, place: place)
            // a light-tone word ("--ah") always joins the word before it: oh--ah, not oh --ah
            if space, prev == "w", mode != 0,
               wordText(it.current, mode: 1, rom: rom, place: place).hasPrefix("--") { space = false }
            out.append(((space ? " " : "") + t, idx))
            prev = "w"; lastText = t
        }
        return out
    }
}
