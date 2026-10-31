import SwiftUI

/// 排句子: an example sentence of a 不熟 word, cut into word cards and shuffled. Tap the cards in the right
/// order (tap a placed card to take it back). The 華語 is shown as a hint; the blue potion shows how close
/// the order is to the real sentence.
struct ScrambleView: View {
    /// 看字排讀音: only the 漢字 sentence is shown, and the cards are its pronunciation (romanization) pieces
    var readingMode = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("sessionSize") private var sessionSize = 10
    @AppStorage(ToneColors.key) private var toneSys = 0

    struct Tile: Identifiable, Equatable {
        let id: Int                 // position in the real sentence
        let han: AttributedString
        let rom: AttributedString
        var reading = false
        /// what has to match: the word and its reading (只看讀音: the reading)
        var text: String { reading ? String(rom.characters) : String(han.characters) + "|" + String(rom.characters) }
        static func == (a: Tile, b: Tile) -> Bool { a.id == b.id }
    }
    struct Puzzle {
        let card: Card
        let example: Example
        let tiles: [Tile]           // in the right order
        let end: String             // the punctuation at the end
    }

    @State private var puzzles: [Puzzle] = []
    @State private var idx = 0
    @State private var pool: [Tile] = []
    @State private var placed: [Tile] = []
    @State private var solved = 0
    @State private var revealed = false
    @State private var loading = true
    @StateObject private var stars = StarField()
    @Namespace private var ns

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if puzzles.isEmpty {
                    Text("不熟的詞裡沒有可以排的例句。").foregroundStyle(T.muted)
                } else if idx >= puzzles.count {
                    summary
                } else {
                    puzzleView(puzzles[idx])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .starBursts(stars)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("結束")
                }
                ToolbarItem(placement: .principal) {
                    if !puzzles.isEmpty && idx < puzzles.count {
                        Text("\(readingMode ? "看字排讀音" : "排句子")　\(idx + 1)／\(puzzles.count)").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
        .onAppear {
            if store.dict == nil && (place >= 0 || toneSys != 0) { store.loadDict() }
            if puzzles.isEmpty { build() }
        }
        .onChange(of: store.dict != nil) { if loading { build() } }
    }

    // MARK: building

    private func build() {
        // local readings and tone colours need the dictionary: wait for it
        if (place >= 0 || toneSys != 0) && store.dict == nil { loading = true; return }
        var out: [Puzzle] = []
        for c in store.unknownCards.shuffled() {
            let xs = c.d.flatMap { $0.x }.shuffled()
            for x in xs {
                if let p = makePuzzle(c, x) { out.append(p); break }
            }
            if out.count >= max(1, sessionSize) { break }
        }
        puzzles = out
        idx = 0; solved = 0
        loading = false
        if !out.isEmpty { setUp(out[0]) }
    }

    /// the sentence cut into its words (the romanization's words, joined by "-"), with the matching 漢字
    private func makePuzzle(_ c: Card, _ x: Example) -> Puzzle? {
        let romA = store.exampleRom(c, x, rom, place)
        let hanA = store.exampleHan(c, x, place)
        // romanization words (split at spaces), without punctuation around them
        var words: [AttributedString] = []
        var cur = AttributedString()
        for run in romA.runs {
            for ch in romA[run.range].characters {
                if ch == " " {
                    if !cur.characters.isEmpty { words.append(cur); cur = AttributedString() }
                } else {
                    var one = AttributedString(String(ch)); one.mergeAttributes(run.attributes)
                    cur += one
                }
            }
        }
        if !cur.characters.isEmpty { words.append(cur) }
        let punct = CharacterSet(charactersIn: ",.!?;:\"“”‘’()（），。！？；：、…")
        func isPunct(_ c: Character) -> Bool { String(c).unicodeScalars.allSatisfy { punct.contains($0) } }
        words = words.compactMap { w in
            var w = w
            while let l = w.characters.last, isPunct(l) { w.characters.removeLast() }
            while let f = w.characters.first, isPunct(f) { w.characters.removeFirst() }
            return w.characters.isEmpty ? nil : w
        }
        guard words.count >= 3, words.count <= 12 else { return nil }
        // the sentence's last punctuation mark, shown after the last card
        let end = romA.characters.last.map { isPunct($0) ? String($0) : "" } ?? ""
        // don't give away the first word by its capital letter
        if let f = words[0].characters.first, f.isUppercase {
            let r = words[0].characters.startIndex..<words[0].characters.index(after: words[0].characters.startIndex)
            words[0].characters.replaceSubrange(r, with: String(f).lowercased())
        }
        // syllables per word ("--" counts as joining, not a syllable)
        let counts = words.map { w in String(w.characters).split(separator: "-", omittingEmptySubsequences: true).count }
        // 漢字 characters (punctuation left out), with their colours
        var hanChars: [AttributedString] = []
        for run in hanA.runs {
            for ch in hanA[run.range].characters where ch.unicodeScalars.first.map({ ConvertEngine.isHan($0.value) }) ?? false {
                var one = AttributedString(String(ch)); one.mergeAttributes(run.attributes)
                hanChars.append(one)
            }
        }
        guard counts.reduce(0, +) == hanChars.count else { return nil }
        var tiles: [Tile] = [], n = 0
        for (i, w) in words.enumerated() {
            var h = AttributedString()
            for k in n..<n + counts[i] { h += hanChars[k] }
            n += counts[i]
            if h.characters.isEmpty { return nil }
            tiles.append(Tile(id: i, han: h, rom: w, reading: readingMode))
        }
        return Puzzle(card: c, example: x, tiles: tiles, end: end)
    }

    private func setUp(_ p: Puzzle) {
        var s = p.tiles.shuffled()
        var tries = 0
        while s.map(\.text) == p.tiles.map(\.text) && tries < 10 { s.shuffle(); tries += 1 }
        pool = s
        placed = []
        revealed = false
    }

    // MARK: checking

    /// how close the order is: the longest run of placed cards that are in the right order
    /// (not necessarily side by side), out of all the cards
    private func closeness(_ p: Puzzle) -> Double {
        let a = placed.map(\.text), b = p.tiles.map(\.text)
        guard !a.isEmpty else { return 0 }
        var dp = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var prev = 0
            for j in 1...b.count {
                let tmp = dp[j]
                dp[j] = x == b[j - 1] ? prev + 1 : max(dp[j], dp[j - 1])
                prev = tmp
            }
        }
        return Double(dp[b.count]) / Double(b.count)
    }

    private func isSolved(_ p: Puzzle) -> Bool { pool.isEmpty && placed.map(\.text) == p.tiles.map(\.text) }

    /// placed card i is not where it belongs (only shown once every card is placed)
    private func wrongAt(_ p: Puzzle, _ i: Int) -> Bool {
        pool.isEmpty && !isSolved(p) && placed[i].text != p.tiles[i].text
    }

    // MARK: views

    private func puzzleView(_ p: Puzzle) -> some View {
        let done = isSolved(p)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if readingMode {
                    // only the 漢字 (the recording and the 華語 once it's done)
                    HStack(alignment: .top, spacing: 10) {
                        if done { PlayButton(path: Audio.examplePath(p.example.n), size: 34) }
                        VStack(alignment: .leading, spacing: 6) {
                            // as the place says it (its own words swapped in), without tone colours (no hints)
                            Text(String(store.exampleHan(p.card, p.example, place).characters))
                                .scaledFont(26, weight: .semibold).foregroundStyle(T.blueInk)
                            if done { Text(p.example.z).ffFont(.subheadline).foregroundStyle(T.muted) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // the 華語, and the recording as a hint
                    HStack(alignment: .top, spacing: 10) {
                        PlayButton(path: Audio.examplePath(p.example.n), size: 34)
                        Text(p.example.z).ffFont(.title3).foregroundStyle(T.glyph)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // how close: the blue potion
                PotionBar(value: closeness(p), height: 22, showMarks: false, label: "排得多接近", palette: .blue)

                // the sentence being built
                VStack(alignment: .leading, spacing: 8) {
                    Text(done ? (revealed ? "答案" : "排對了！") : (readingMode ? "照上面的字，把讀音照順序排" : "點下面的詞，照順序排"))
                        .ffFont(.caption, .bold).foregroundStyle(done ? T.greenInk : T.muted)
                    FlowLayout(spacing: 8, lineSpacing: 10) {
                        ForEach(Array(placed.enumerated()), id: \.element.id) { i, t in
                            Button { take(t) } label: { tileView(t, wrong: wrongAt(p, i), right: done) }
                                .buttonStyle(.plain)
                                .disabled(done)
                                .matchedGeometryEffect(id: t.id, in: ns)
                        }
                        if done && !p.end.isEmpty {
                            Text(p.end).ffFont(.title2).foregroundStyle(T.muted).padding(.top, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(done ? T.greenEdge : T.fnEdge, style: StrokeStyle(lineWidth: 2, dash: placed.isEmpty ? [6, 5] : [])))
                }

                // the cards still to place
                if !pool.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 10) {
                        ForEach(pool) { t in
                            Button { put(t) } label: { tileView(t, wrong: false, right: false) }
                                .buttonStyle(.plain)
                                .matchedGeometryEffect(id: t.id, in: ns)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if pool.isEmpty && !done {
                    Text("紅框的詞位置不對，點一下拿回來再排。").ffFont(.footnote).foregroundStyle(T.rustInk)
                }

                HStack(spacing: 10) {
                    if !done {
                        Button { withAnimation(.snappy) { pool = (pool + placed).shuffled(); placed = [] } } label: {
                            Label("重來", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .softButton()
                        .disabled(placed.isEmpty)
                        Button { withAnimation(.snappy) { revealed = true; placed = p.tiles; pool = [] } } label: {
                            Label("看答案", systemImage: "eye").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .softButton()
                    } else {
                        Button { next() } label: {
                            Label(idx + 1 < puzzles.count ? "下一句" : "完成", systemImage: "arrow.right")
                                .ffFont(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .prominentButton(T.greenEdge)
                    }
                }
                .padding(.top, 4)

                // the word the sentence came from
                if done {
                    HStack(spacing: 6) {
                        Text("出自").foregroundStyle(T.muted)
                        Text(p.card.h).foregroundStyle(T.blueInk)
                    }
                    .ffFont(.footnote)
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private func tileView(_ t: Tile, wrong: Bool, right: Bool) -> some View {
        VStack(spacing: 3) {
            if readingMode {
                Text(colorless(t.rom, T.greenInk)).latFont(19).toneGlow()
                    .padding(.vertical, 4)
            } else {
                Text(colorless(t.han, T.glyph)).ffFont(.title3, .semibold).toneGlow()
                Text(colorless(t.rom, T.greenInk)).latFont(14).toneGlow()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(right ? T.green.opacity(0.85) : T.key.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(wrong ? T.rustEdge : (right ? T.greenEdge : T.keyEdge), lineWidth: wrong ? 2.5 : 1.5))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .contentShape(Rectangle())
    }

    /// text without a colour of its own gets `ink`
    private func colorless(_ a: AttributedString, _ ink: Color) -> AttributedString {
        var a = a
        for run in a.runs where run.swiftUI.foregroundColor == nil { a[run.range].swiftUI.foregroundColor = ink }
        return a
    }

    private func put(_ t: Tile) {
        guard let p = puzzles[safe: idx] else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            pool.removeAll { $0.id == t.id }
            placed.append(t)
        }
        if isSolved(p) && !revealed {
            solved += 1
            // a little celebration: stars from the middle of the screen, and the sentence read aloud
            for i in 0..<4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                    stars.burst(at: CGPoint(x: CGFloat.random(in: 80...320), y: CGFloat.random(in: 200...380)))
                }
            }
            Player.shared.play(Audio.examplePath(p.example.n))
        }
    }

    private func take(_ t: Tile) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            placed.removeAll { $0.id == t.id }
            pool.append(t)
        }
    }

    private func next() {
        idx += 1
        if idx < puzzles.count { setUp(puzzles[idx]) }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(ToneColors.yellow)
            Text("排好了 \(solved)／\(puzzles.count) 句").ffFont(.title2, .bold).foregroundStyle(T.glyph)
            Button { build() } label: {
                Label("再來一輪", systemImage: "arrow.clockwise").ffFont(.headline).frame(maxWidth: 260, minHeight: 44)
            }
            .prominentButton(T.greenEdge)
            Button("結束") { dismiss() }.foregroundStyle(T.muted)
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
