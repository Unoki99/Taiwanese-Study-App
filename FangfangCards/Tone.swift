import SwiftUI

// 聲調顏色: with the 聲調 button on, every syllable (漢字, 羅馬字, 方音) is coloured by the tone it is
// actually said in, after tone sandhi.
//
// Every syllable takes its sandhi tone, except:
//  - the last syllable before punctuation or at the end (the end of a tone group)
//  - the last syllable of a noun (名詞, from the word's main meaning)
//  - the last syllable of a 時間詞
//  - the last syllable of a verb that ends with a noun (食飯: 飯 is a noun)
//  - the syllable before "--"
// Before 仔 a syllable takes its own change: 2, 3 → 1; 1, 5, 7, 8 and 4 ending in h → 7; 4 ending in p/t/k → 8
// (this wins over the "keeps its tone" cases above, but not over "--").
// A syllable joined to the next one with a single "-" always changes (女權 lù-khuán), and a word listed as
// both 名詞 and 量詞 right after a 數詞 or 代詞 is a 量詞 there (it changes too).
// Syllables after "--" are said in the light tone: grey.
// Sandhi follows the 腔口: 通行 and the 漳 / 混合 places 2→1, 5→7, 8→4 (8 ending in h → 3); the 泉 places 2→5, 5→3, 8→3.
// Tone 6 (鹿港 and other places that keep it) → 3.

enum ToneColors {
    static let key = "toneColors"
    /// 0 = off, 7 = 七聲, 5 = 五聲
    static var system: Int { UserDefaults.standard.integer(forKey: key) }
    static let marksKey = "toneMarksSandhi"
    /// the tone marks show the tone after sandhi too (tsia̍h-pn̄g → tsià-pn̄g)
    static var marks: Bool { UserDefaults.standard.object(forKey: marksKey) as? Bool ?? true }

    static let red = Color(hex: 0xff6b6b), purple = Color(hex: 0xc39bff), blue = Color(hex: 0x6eaaff)
    static let orange = Color(hex: 0xffa94d), green = Color(hex: 0x6fdc7f), yellow = Color(hex: 0xffe066)
    static let pink = Color(hex: 0xff8cc6), light = Color(hex: 0x8e8e93)
    /// tone 6 (鹿港 and other places that keep it): teal, the one hue the other tones don't use
    static let teal = Color(hex: 0x4fd8c4)

    /// the colour of a realized tone (0 = light tone); nil = leave the text colour as it is
    static func color(_ t: Int, _ sys: Int) -> Color? {
        if t == 0 { return light }
        if sys == 5 {
            switch t {
            case 1, 8: return red
            case 2: return purple
            case 3, 4: return blue
            case 5: return green
            case 6: return teal
            case 7: return yellow
            default: return nil
            }
        }
        switch t {
        case 1: return red
        case 2: return purple
        case 3: return blue
        case 4: return orange
        case 5: return green
        case 6: return teal
        case 7: return yellow
        case 8: return pink
        default: return nil
        }
    }
}

/// one syllable while working out the tones of a stretch of text
struct ToneUnit {
    var code: String
    var light = false          // after "--": light tone
    var beforeLight = false    // right before "--": keeps its tone
    var keep = false           // last syllable of a noun / 時間詞 / verb ending in a noun: keeps its tone
    var phraseEnd = false      // before punctuation or at the end: keeps its tone
    var beforeA = false        // right before 仔: 仔-sandhi
}

extension Dict {
    /// the tone written in a syllable code, and whether a checked syllable ends in h (not p / t / k)
    func toneOf(_ code: String) -> (tone: Int, h: Bool) {
        guard let last = code.last, let t = last.wholeNumberValue else { return (0, false) }
        let body = code.dropLast()
        let hasVowel = body.contains { "iuaoøeIUɨəɵ".contains($0) }
        let stop = hasVowel && (body.last.map { "BDG".contains($0) } ?? false)
        return (t, !stop)
    }

    /// the syllable written in the tone it's said in (when that spelling exists)
    func sandhiCode(_ code: String, _ tone: Int) -> String {
        let (t, h) = toneOf(code)
        guard tone > 0, t != tone else { return code }
        // a syllable ending in p / t / k can only be written in tone 4 or 8 (ām would be a different syllable)
        if (t == 4 || t == 8) && !h && !(tone == 4 || tone == 8) { return code }
        let n = String(code.dropLast()) + String(tone)
        return isCode(n) ? n : code
    }

    /// 泉-leaning places use 5→3 and 8→3
    func quanSandhi(_ place: Int) -> Bool { place >= 0 && place < raw.places.count && raw.places[place].contains("泉") }

    /// the tone a syllable is said in when it changes (tone sandhi)
    func sandhiTone(_ code: String, _ place: Int) -> Int {
        let (t, h) = toneOf(code)
        let quan = quanSandhi(place)
        switch t {
        case 1: return 7
        case 2: return quan ? 5 : 1
        case 3: return 2
        case 5: return quan ? 3 : 7
        case 7, 6: return 3
        case 4: return h ? 2 : 8
        case 8: return h ? 3 : (quan ? 3 : 4)
        default: return t
        }
    }

    /// the tone a syllable is said in right before 仔
    func aSandhiTone(_ code: String) -> Int {
        let (t, h) = toneOf(code)
        switch t {
        case 2, 3: return 1
        case 1, 5, 6, 7, 8: return 7
        case 4: return h ? 7 : 8
        default: return t
        }
    }

    /// realized tone of each syllable (0 = light tone)
    func realizedTones(_ units: [ToneUnit], _ place: Int) -> [Int] {
        units.map { u in
            if u.light { return 0 }
            if u.beforeA && !u.beforeLight { return aSandhiTone(u.code) }
            if u.keep || u.phraseEnd || u.beforeLight { return toneOf(u.code).tone }
            return sandhiTone(u.code, place)
        }
    }

    /// a word used as a 量詞 here, so its tone changes:
    /// - listed as both 名詞 and 量詞, right after a 數詞 or 代詞 (一隻, 這擺);
    /// - a one-syllable 名詞 between a 代詞 and another 名詞 (這款種: 款 is a 量詞 here, even though the
    ///   dictionary only lists it as a 名詞)
    func classifierHere(_ key: String?, after prev: String?, before next: String? = nil) -> Bool {
        guard let key, let pos = raw.pos[key], pos.contains("名詞"),
              let prev, let pp = raw.pos[prev] else { return false }
        if pos.contains("量詞") && (pp.contains("數詞") || pp.contains("代詞")) { return true }
        if pp.contains("代詞"), Dict.codesOf(key).split(separator: " ").count == 1,
           let next, let np = raw.pos[next], np.contains("名詞") { return true }
        return false
    }

    /// nouns, 時間詞 and verbs ending in a noun keep the tone of their last syllable
    /// (`after` = the word before it, to tell a 量詞 from a 名詞)
    func keepsLastTone(_ key: String?, after prev: String? = nil, before next: String? = nil) -> Bool {
        guard let key, let pos = raw.pos[key] else { return false }
        if classifierHere(key, after: prev, before: next) { return false }
        if pos.contains("時間詞") { return true }
        let main = pos.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if main.contains("名詞") { return true }
        if main.contains("動詞") {
            let hs = Array(Dict.hanOf(key)), cs = Dict.codesOf(key).split(separator: " ").map(String.init)
            guard hs.count == cs.count, hs.count > 1 else { return false }
            for L in 1..<hs.count {
                let k = String(hs.suffix(L)) + "\t" + cs.suffix(L).joined(separator: " ")
                if let p = raw.pos[k], baseKeys.contains(k),
                   (p.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? "").contains("名詞") { return true }
            }
        }
        return false
    }

    /// a word's syllables as tone units, from its tokens ("--" marks the light tone)
    func toneUnits(tokens: [String], key: String?, after prev: String? = nil, before next: String? = nil) -> [ToneUnit] {
        var out: [ToneUnit] = []
        var lightNext = false
        for t in tokens {
            let c = t.hasPrefix("^") ? String(t.dropFirst()) : t
            if isCode(c) {
                out.append(ToneUnit(code: c, light: lightNext))
                // a light tone goes on through the syllables joined to it ("tshut--khì-lâi")
            } else if t == "--" {
                if !out.isEmpty { out[out.count - 1].beforeLight = true }
                lightNext = true
            } else if t == "_" {
                lightNext = false
            }
        }
        if keepsLastTone(key, after: prev, before: next), !out.isEmpty { out[out.count - 1].keep = true }
        // 仔 inside the word
        if let key {
            let hs = Array(Dict.hanOf(key))
            if hs.count == out.count { for i in out.indices.dropLast() where hs[i + 1] == "仔" { out[i].beforeA = true } }
        }
        return out
    }

    /// a word on its own (headword, card, list): its last syllable ends the phrase
    func wordTones(_ key: String, _ place: Int) -> [Int] {
        var u = toneUnits(tokens: tokensFor(key, place), key: key)
        if !u.isEmpty { u[u.count - 1].phraseEnd = true }
        return realizedTones(u, place)
    }

    /// a reading drawn syllable by syllable in its tone colours (same text as render)
    func toneText(_ tokens: [String], _ sys: Int, _ place: Int, tones: [Int], system: Int) -> AttributedString {
        var out = AttributedString()
        var prevCode = false, n = 0
        for t in tokens {
            let cap = t.hasPrefix("^"), c = cap ? String(t.dropFirst()) : t
            if isCode(c) {
                if sys != 3 && prevCode { out += AttributedString("-") }
                let shown = ToneColors.marks && n < tones.count ? sandhiCode(c, tones[n]) : c
                var s = syl(shown, sys, place)
                if cap && sys != 3 { s = s.prefix(1).uppercased() + s.dropFirst() }
                var a = AttributedString(s)
                if n < tones.count, let col = ToneColors.color(tones[n], system) { a.swiftUI.foregroundColor = col }
                out += a; n += 1; prevCode = true
            } else if t == "--" { if sys != 3 { out += AttributedString("--") }; prevCode = false }
            else if t == "_" { out += AttributedString(" "); prevCode = false }
            else if t.hasPrefix("~") { out += AttributedString(String(t.dropFirst())); prevCode = false }
            else { out += AttributedString(t); prevCode = false }
        }
        return out
    }

    /// 漢字 coloured one character per syllable (characters that aren't 漢字 keep the base colour)
    func hanToneText(_ han: String, tones: [Int], system: Int, base: Color? = nil) -> AttributedString {
        var out = AttributedString(), n = 0
        for ch in han {
            var a = AttributedString(String(ch))
            if ch.unicodeScalars.first.map({ ConvertEngine.isHan($0.value) }) == true {
                if n < tones.count, let col = ToneColors.color(tones[n], system) { a.swiftUI.foregroundColor = col }
                else if let base { a.swiftUI.foregroundColor = base }
                n += 1
            } else if let base { a.swiftUI.foregroundColor = base }
            out += a
        }
        return out
    }

    /// a word's reading in tone colours
    func wordToneText(_ key: String, _ sys: Int, _ place: Int, system: Int) -> AttributedString {
        toneText(tokensFor(key, place), sys, place, tones: wordTones(key, place), system: system)
    }
    /// a word's 漢字 in tone colours
    func wordHanToneText(_ key: String, _ place: Int, system: Int, base: Color? = nil) -> AttributedString {
        hanToneText(Dict.hanOf(key), tones: wordTones(key, place), system: system, base: base)
    }

    // MARK: example sentences

    /// an example as shown for the place (the place's own words swapped in, its readings), with the tone
    /// of every syllable: (漢字, template, tones)
    func exampleTones(_ han: String, _ tpl: String, place: Int, zh: String?) -> (han: String, tpl: String, tones: [Int]) {
        var h = han, t = tpl
        if place >= 0 {
            let loc = localizedExample(han, tpl, place, zh: zh)
            h = loc.han
            t = dialectTemplate(loc.han, loc.tpl, place)
        }
        // codes and what comes between them
        var codes: [String] = [], seps: [String] = []
        var i = t.startIndex, prevEnd = t.startIndex
        while let open = t[i...].firstIndex(of: "{"), let close = t[open...].firstIndex(of: "}") {
            var c = String(t[t.index(after: open)..<close])
            if c.hasPrefix("^") { c.removeFirst() }
            if c.hasPrefix("?") || c.hasPrefix("!") { c.removeFirst() }
            codes.append(c); seps.append(String(t[prevEnd..<open]))
            prevEnd = t.index(after: close); i = prevEnd
        }
        let tail = String(t[prevEnd...])
        guard !codes.isEmpty else { return (h, t, []) }
        // which word each syllable belongs to
        let clean = t.replacingOccurrences(of: "{?", with: "{").replacingOccurrences(of: "{!", with: "{")
            .replacingOccurrences(of: "{^?", with: "{^").replacingOccurrences(of: "{^!", with: "{^")
        var keepAt = Set<Int>()
        var n = 0
        // the words with 漢字, and whether punctuation comes before each (the word before / after across
        // punctuation doesn't count)
        var words: [(key: String?, count: Int, afterPunct: Bool)] = []
        var sawPunct = false
        for p in exampleWords(h, clean) {
            let count = p.text.unicodeScalars.filter { ConvertEngine.isHan($0.value) }.count
            if count == 0 {
                if p.text.unicodeScalars.contains(where: { CharacterSet.punctuationCharacters.contains($0) }) { sawPunct = true }
                continue
            }
            words.append((p.key, count, sawPunct)); sawPunct = false
        }
        for (w, word) in words.enumerated() {
            let prevKey = w > 0 && !word.afterPunct ? words[w - 1].key : nil
            let nextKey = w + 1 < words.count && !words[w + 1].afterPunct ? words[w + 1].key : nil
            if keepsLastTone(word.key, after: prevKey, before: nextKey) { keepAt.insert(n + word.count - 1) }
            n += word.count
        }
        let hanChars = h.filter { $0.unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false }.map { $0 }
        var units: [ToneUnit] = []
        for (j, c) in codes.enumerated() {
            var u = ToneUnit(code: c)
            let sep = seps[j]
            u.light = sep == "--" || (sep == "-" && (units.last?.light ?? false))
            let next = j + 1 < codes.count ? seps[j + 1] : tail
            u.beforeLight = next == "--"
            u.phraseEnd = j + 1 == codes.count || next.contains(where: { !" -".contains($0) })
            // joined to the next syllable with one "-" (lù-khuán): it always changes
            u.keep = keepAt.contains(j) && next != "-"
            u.beforeA = j + 1 < hanChars.count && hanChars[j + 1] == "仔"
            units.append(u)
        }
        return (h, t, realizedTones(units, place))
    }

    /// an example's 羅馬字 / 方音 in tone colours
    func sentenceToneText(_ han: String, _ tpl: String, _ sys: Int, place: Int, zh: String?, system: Int) -> AttributedString {
        let ex = exampleTones(han, tpl, place: place, zh: zh)
        var out = AttributedString()
        var rest = Substring(ex.tpl), n = 0
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += AttributedString(String(rest[..<open]))
            var c = String(rest[rest.index(after: open)..<close])
            let cap = c.hasPrefix("^")
            if cap { c.removeFirst() }
            if c.hasPrefix("?") || c.hasPrefix("!") { c.removeFirst() }
            if ToneColors.marks, n < ex.tones.count, isCode(c) { c = sandhiCode(c, ex.tones[n]) }
            var s = isCode(c) ? syl(c, sys, place) : c
            if cap { s = s.prefix(1).uppercased() + s.dropFirst() }
            var a = AttributedString(s)
            if n < ex.tones.count, let col = ToneColors.color(ex.tones[n], system) { a.swiftUI.foregroundColor = col }
            out += a; n += 1
            rest = rest[rest.index(after: close)...]
        }
        out += AttributedString(String(rest))
        return out
    }

    /// an example's 漢字 (the place's own words swapped in) in tone colours
    func sentenceHanToneText(_ han: String, _ tpl: String, place: Int, zh: String?, system: Int, base: Color? = nil) -> AttributedString {
        let ex = exampleTones(han, tpl, place: place, zh: zh)
        return hanToneText(ex.han, tones: ex.tones, system: system, base: base)
    }
}

/// 聲調 button (top bar, next to the 腔口): off / 七聲 / 五聲
struct ToneMenu: View {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.marksKey) private var marks = true
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    @AppStorage("glass2") private var glassOn = false
    var body: some View {
        Menu {
            Picker("聲調顏色", selection: $system) {
                Text("關").tag(0)
                Text("七聲（1 2 3 4 5 7 8）").tag(7)
                Text("五聲（1=8、3=4）").tag(5)
            }
            .pickerStyle(.inline)
            if system != 0 {
                Toggle("聲調符號照變調寫", isOn: $marks)
                Toggle("聲調光暈", isOn: $glow)
            }
        } label: {
            label
        }
        .accessibilityLabel("聲調顏色")
        #if targetEnvironment(macCatalyst)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    private var dots: some View {
        HStack(spacing: 2) {
            if system == 0 {
                #if targetEnvironment(macCatalyst)
                Text("聲調").ffFont(.subheadline, .bold).foregroundStyle(T.glyph)
                #else
                Text("調").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                #endif
            } else {
                ForEach(system == 5 ? [1, 2, 3, 5, 7] : [1, 2, 3, 4, 5, 7, 8], id: \.self) { t in
                    Circle().fill(ToneColors.color(t, system) ?? T.muted).frame(width: 5, height: 5)
                }
            }
        }
    }

    @ViewBuilder private var label: some View {
        #if targetEnvironment(macCatalyst)
        capsule
        #else
        if glassOn, #available(iOS 26.0, *) { dots } else { capsule }
        #endif
    }
    private var capsule: some View {
        dots
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(T.fn))
            .overlay(Capsule().stroke(T.fnEdge, lineWidth: 2))
    }
}


extension ToneColors {
    /// the glow around coloured letters (設定 → 顯示 → 聲調光暈). The Mac draws it without blur: there every blur
    /// is worked out again whenever anything on the page moves (a word swelling), which made hovering slow.
    static let glowKey = "toneGlow"
    #if targetEnvironment(macCatalyst)
    static let glowStandard = true      // the Mac has its own cheaper glow (no blur)
    #else
    static let glowStandard = true
    #endif
}

/// 聲調顏色 on: the coloured letters glow a little in their own colour
struct ToneGlow: ViewModifier {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    @ViewBuilder func body(content: Content) -> some View {
        if system != 0 && glow {
            #if targetEnvironment(macCatalyst)
            // Mac: no blur (the Mac works every blur out again whenever anything on the page moves). A soft
            // halo instead: faint copies of the letters, a little to each side, in a ring of 8 and a wider
            // ring of 8. Drawing letters is cheap; only the colours spread out around them.
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let r: CGFloat = i < 8 ? 1.4 : 3.0
                    let a = Double(i % 8) * .pi / 4 + (i < 8 ? 0 : .pi / 8)
                    content
                        .offset(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a)))
                        .opacity(i < 8 ? 0.16 : 0.07)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                content
            }
            #else
            // a ZStack (not .background) so the blurred copies get the same width as the text and wrap the
            // same way; a background copy is laid out again at the text's measured size and can wrap differently
            ZStack {
                content.blur(radius: 5).opacity(0.9).allowsHitTesting(false).accessibilityHidden(true)
                content.blur(radius: 1.5).opacity(0.6).allowsHitTesting(false).accessibilityHidden(true)
                content
            }
            #endif
        } else {
            content
        }
    }
}
extension View {
    func toneGlow() -> some View { modifier(ToneGlow()) }
}
