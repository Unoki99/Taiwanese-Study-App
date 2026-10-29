import SwiftUI

/// 詞典 → 文法: write a sentence, see how normal it looks next to the dictionary's own sentences
struct GrammarPane: View {
    let dict: Dict
    @AppStorage("grammarText") private var text = ""
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var grammar: Grammar?
    @State private var missing = false
    @State private var result: GrammarResult?
    @State private var busy = false
    @State private var tapped: DictKey?
    @FocusState private var focused: Bool

    private static let samples = ["我欲去學校", "食飽我矣", "阿公睏佇厝內", "伊昨昏去臺北買物件"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                input
                if missing {
                    note("這個版本沒有文法資料（grammar.json）。請先跑 build-data.sh，再重新建置 app。")
                } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    samplesView
                } else if let r = result {
                    verdict(r)
                    words(r)
                    if let w = r.worst { oddest(r, w) }
                    if let s = r.suggestion { suggestion(s, r.suggestionScore ?? 0) }
                    examples(r)
                } else if busy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Text("這不是 AI，是從教育部辭典大約一萬八千句例句算出來的：哪一種詞類後面常接哪一種，常用的詞前後常出現什麼。結果只是參考，少見不一定就是錯。")
                    .ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .wordOpener(dict, $tapped)
        .onAppear {
            if grammar == nil {
                grammar = Grammar.load(dict: dict)
                missing = grammar == nil
            }
        }
        .task(id: text) { await run() }
    }

    // MARK: input

    private var input: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("寫一句台語（漢字或羅馬字）…")
                    .foregroundStyle(T.muted)
                    .padding(.horizontal, 5).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .scaledFont(18)
                .frame(minHeight: 80, maxHeight: 160)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(8)
        .glassSurface(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .scaledFont(18).foregroundStyle(T.muted).padding(10)
            }
        }
    }

    private var samplesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("試試看").ffFont(.caption).foregroundStyle(T.muted)
            FlowLayout(spacing: 8) {
                ForEach(Self.samples, id: \.self) { s in
                    Button { text = s } label: {
                        Text(s).scaledFont(17).foregroundStyle(T.blueInk)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(T.blue.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func run() async {
        let t = text
        guard let g = grammar, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { result = nil; return }
        busy = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        let r = await Task.detached(priority: .userInitiated) { g.analyse(t) }.value
        if Task.isCancelled { return }
        result = r
        busy = false
    }

    // MARK: result

    private func card<C: View>(_ fill: Color = T.fn.opacity(0.6), @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(fill))
    }

    private func note(_ s: String) -> some View {
        card { Text(s).ffFont(.footnote).foregroundStyle(T.muted) }
    }

    private func verdict(_ r: GrammarResult) -> some View {
        let (icon, title, fill, ink): (String, String, Color, Color) = {
            switch r.level {
            case 2: return ("checkmark.circle.fill", "通順", T.green, T.greenInk)
            case 1: return ("questionmark.circle.fill", "有點少見", T.olive, T.oliveInk)
            default: return ("exclamationmark.triangle.fill", "可能有問題", T.rust, T.rustInk)
            }
        }()
        return card(fill.opacity(0.8)) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).ffFont(.headline)
                Spacer(minLength: 0)
                Text("\(Int((r.score * 100).rounded()))%").latFont(20).bold()
            }
            .foregroundStyle(ink)
            Text("比 \(Int((r.score * 100).rounded()))% 的辭典例句通順")
                .ffFont(.footnote).foregroundStyle(ink.opacity(0.85))
            ProgressView(value: r.score).tint(ink)
        }
    }

    private func className(_ t: String) -> String {
        switch t {
        case "?": return "辭典無"
        case "標點": return "標點"
        default: return t
        }
    }

    /// is token i next to the oddest step?
    private func odd(_ r: GrammarResult, _ i: Int) -> Bool {
        guard let w = r.worst, r.level < 2 else { return false }
        return i == w - 1 || i == w
    }

    private func words(_ r: GrammarResult) -> some View {
        card {
            Text("詞和詞類").ffFont(.caption).foregroundStyle(T.muted)
            FlowLayout(spacing: 6, lineSpacing: 8) {
                ForEach(Array(r.tokens.enumerated()), id: \.offset) { i, t in
                    wordChip(t, i < r.tags.count ? r.tags[i] : "?", odd: odd(r, i))
                }
            }
        }
    }

    private func wordChip(_ t: GToken, _ tag: String, odd: Bool) -> some View {
        let chip = VStack(spacing: 2) {
            Text(t.text).scaledFont(20, weight: .semibold)
                .foregroundStyle(t.key == nil && !t.punct ? T.guessInk : T.glyph)
            if let k = t.key {
                Text(dict.codes(Dict.codesOf(k), min(max(rom, 0), 2), place)).latFont(12).foregroundStyle(T.greenInk)
            }
            Text(className(tag)).ffFont(.caption2).foregroundStyle(T.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(odd ? T.rust.opacity(0.7) : T.key.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(odd ? T.rustEdge : .clear, lineWidth: 1.5))
        return Group {
            if let k = t.key {
                Button { tapped = DictKey(k: k) } label: { chip }.buttonStyle(.plain)
            } else { chip }
        }
    }

    private func oddest(_ r: GrammarResult, _ w: Int) -> some View {
        let a = w > 0 ? r.tokens[w - 1] : nil, b = w < r.tokens.count ? r.tokens[w] : nil
        let ta = w > 0 ? className(r.tags[w - 1]) : "", tb = w < r.tags.count ? className(r.tags[w]) : ""
        let line: String = {
            if let a, let b { return "「\(a.text)」（\(ta)）後面接「\(b.text)」（\(tb)）" }
            if let b { return "用「\(b.text)」（\(tb)）開頭" }
            if let a { return "用「\(a.text)」（\(ta)）結尾" }
            return ""
        }()
        return Group {
            if r.level < 2 {
                card {
                    Text("最奇怪的地方").ffFont(.caption).foregroundStyle(T.muted)
                    Text(line).ffFont(.body).foregroundStyle(T.rustInk)
                }
            }
        }
    }

    private func sentence(_ toks: [GToken]) -> String { toks.map(\.text).joined() }

    private func suggestion(_ s: [GToken], _ p: Double) -> some View {
        card(T.blue.opacity(0.6)) {
            Text("換個位置試試看").ffFont(.caption).foregroundStyle(T.blueInk.opacity(0.8))
            Button { text = sentence(s) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(sentence(s)).scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                    Spacer(minLength: 8)
                    Text("\(Int((p * 100).rounded()))%").latFont(15).foregroundStyle(T.blueInk)
                    Image(systemName: "arrow.uturn.up").ffFont(.footnote, .bold).foregroundStyle(T.blueInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("點一下換做這句").ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    /// real sentences from the dictionary with the words at the oddest spot (or every word, if it's fine)
    private func examples(_ r: GrammarResult) -> some View {
        var keys: [String] = []
        if let w = r.worst, r.level < 2 {
            for i in [w - 1, w] where i >= 0 && i < r.tokens.count { if let k = r.tokens[i].key { keys.append(k) } }
        }
        if keys.isEmpty { keys = r.tokens.compactMap(\.key) }
        var seen = Set<String>()
        keys = keys.filter { seen.insert($0).inserted }
        let hits = Array(dict.sentences(with: keys, limit: 60).prefix(6))
        return Group {
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("辭典裡的例句").ffFont(.caption).foregroundStyle(T.muted)
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                        card(T.fn.opacity(0.55)) {
                            ExampleBlock(dict: dict, ex: h.ex, own: h.word, boxedOwn: true, onWord: { tapped = DictKey(k: $0) })
                        }
                    }
                }
            }
        }
    }
}
