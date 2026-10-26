import SwiftUI

enum QuizKind: CaseIterable {
    case meaningToWord   // 華語意思 → 選台語詞
    case wordToMeaning   // 台語詞 → 選意思
    case listen          // 聽發音 → 選詞
    case fillBlank       // 例句填空
    case romanization    // 漢字 → 選讀音
}

struct Question: Identifiable {
    let id = UUID()
    let card: Card
    let kind: QuizKind
    let options: [Card]
    let example: Example?
}

struct StudyView: View {
    /// true: only 例句填空 (fill in the blank in example sentences)
    var blanksOnly = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("goal") private var goal = 3
    @AppStorage("sessionSize") private var sessionSize = 10

    @State private var queue: [Question] = []
    @State private var idx = 0
    @State private var chosen: Card?
    @State private var right = 0
    @State private var wrong = 0
    @State private var learned: [Card] = []
    @State private var retried: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if queue.isEmpty {
                    Text(blanksOnly ? "不熟的詞裡沒有可以填空的例句。" : "沒有不熟的詞可以練習。").foregroundStyle(T.muted)
                } else if idx >= queue.count {
                    summary
                } else {
                    question(queue[idx])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("結束")
                }
                ToolbarItem(placement: .principal) {
                    if !queue.isEmpty && idx < queue.count {
                        ProgressView(value: Double(idx), total: Double(queue.count))
                            .tint(T.greenInk).frame(width: 160)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
        .onAppear { if queue.isEmpty { start() } }
    }

    // MARK: building a session

    private func start() {
        if blanksOnly { startBlanks(); return }
        let words = store.unknownCards
            .shuffled()
            .sorted { store.streak($0) < store.streak($1) }
            .prefix(max(1, sessionSize))
        var first: [Question] = [], second: [Question] = []
        for c in words {
            let ks = kinds(for: c).shuffled()
            if let k = ks.first { first.append(make(c, k)) }
            if ks.count > 1 { second.append(make(c, ks[1])) }
        }
        queue = first.shuffled() + second.shuffled()
        idx = 0; chosen = nil; right = 0; wrong = 0; learned = []; retried = []
    }

    /// 例句填空 only: one sentence per word, a second (different) sentence later in the round when there is one
    private func startBlanks() {
        let words = store.unknownCards
            .filter { !$0.blankExamples.isEmpty }
            .shuffled()
            .sorted { store.streak($0) < store.streak($1) }
            .prefix(max(1, sessionSize))
        var first: [Question] = [], second: [Question] = []
        for c in words {
            let xs = c.blankExamples.shuffled()
            let opts = (store.distractors(for: c) + [c]).shuffled()
            first.append(Question(card: c, kind: .fillBlank, options: opts, example: xs[0]))
            if xs.count > 1 {
                second.append(Question(card: c, kind: .fillBlank, options: (store.distractors(for: c) + [c]).shuffled(), example: xs[1]))
            }
        }
        queue = first.shuffled() + second.shuffled()
        idx = 0; chosen = nil; right = 0; wrong = 0; learned = []; retried = []
    }

    private func kinds(for c: Card) -> [QuizKind] {
        QuizKind.allCases.filter {
            switch $0 {
            case .listen: return c.a != nil
            case .fillBlank: return !c.blankExamples.isEmpty
            default: return !c.d.isEmpty
            }
        }
    }

    private func make(_ c: Card, _ k: QuizKind) -> Question {
        Question(card: c, kind: k,
                 options: (store.distractors(for: c) + [c]).shuffled(),
                 example: k == .fillBlank ? c.blankExamples.randomElement() : nil)
    }

    // MARK: one question

    @ViewBuilder
    private func question(_ q: Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                prompt(q)
                options(q)
                if let c = chosen { feedback(q, picked: c) }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task(id: q.id) {
            if q.kind == .listen, let a = q.card.a { Player.shared.play(Audio.wordPath(a)) }
        }
    }

    @ViewBuilder
    private func prompt(_ q: Question) -> some View {
        let c = q.card
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                switch q.kind {
                case .meaningToWord:
                    label("這個意思的台語是？")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let p = c.d.first?.p, !p.isEmpty { Chip(text: p) }
                        Text(c.firstMeaning).font(.title3).foregroundStyle(T.glyph)
                    }
                case .wordToMeaning:
                    label("這個詞是什麼意思？")
                    HStack {
                        Text(c.h).font(.system(size: 52, weight: .medium)).foregroundStyle(T.blueInk)
                        Spacer()
                        if let a = c.a { PlayButton(path: Audio.wordPath(a), size: 44) }
                    }
                    Text(store.cardRom(c, rom, place)).font(T.lat(24)).foregroundStyle(T.greenInk)
                case .listen:
                    label("聽發音，選出正確的詞")
                    HStack {
                        Spacer()
                        if let a = c.a { PlayButton(path: Audio.wordPath(a), size: 84) }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                case .fillBlank:
                    label("例句填空")
                    if let x = q.example {
                        Text(x.bh ?? x.h).font(.title3).foregroundStyle(T.blueInk)
                        if let br = x.br { Text(br[min(max(rom, 0), 2)]).font(T.lat(17)).foregroundStyle(T.greenInk) }
                        Text(x.z).font(.subheadline).foregroundStyle(T.muted)
                        HStack(spacing: 8) {
                            PlayButton(path: Audio.examplePath(x.n), size: 28)
                            Text("聽例句（提示）").font(.caption).foregroundStyle(T.muted)
                        }
                    }
                case .romanization:
                    label("這個詞怎麼唸？")
                    Text(c.h).font(.system(size: 60, weight: .medium)).foregroundStyle(T.blueInk)
                    Text(c.firstMeaning).font(.footnote).foregroundStyle(T.muted).lineLimit(2)
                }
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.bold)).foregroundStyle(T.oliveInk)
    }

    @ViewBuilder
    private func options(_ q: Question) -> some View {
        let wide = q.kind == .wordToMeaning || q.kind == .romanization
        let cols = wide ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(q.options) { o in
                Button { pick(o, in: q) } label: { optionLabel(o, q) }
                    .buttonStyle(.plain)
                    .disabled(chosen != nil)
            }
        }
    }

    private func optionLabel(_ o: Card, _ q: Question) -> some View {
        let answered = chosen != nil
        let isRight = o == q.card
        let isPicked = chosen == o
        let fill: Color = answered && isRight ? T.green : (answered && isPicked ? T.rust : T.key)
        let edge: Color = answered && isRight ? T.greenEdge : (answered && isPicked ? T.rustEdge : T.keyEdge)
        return VStack(spacing: 4) {
            switch q.kind {
            case .wordToMeaning:
                Text(o.firstMeaning).foregroundStyle(T.glyph).lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .romanization:
                Text(store.cardRom(o, rom, place)).font(T.lat(22)).foregroundStyle(T.greenInk)
            default:
                Text(o.h).font(.system(size: 30, weight: .medium)).foregroundStyle(T.blueInk)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if answered {
                    Text(store.cardRom(o, rom, place)).font(T.lat(14)).foregroundStyle(T.greenInk)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64)
        .glassSurface(RoundedRectangle(cornerRadius: 18),
                      tint: answered && isRight ? T.greenEdge.opacity(0.75)
                          : (answered && isPicked ? T.rustEdge.opacity(0.75) : T.key.opacity(0.35)),
                      interactive: !answered,
                      fallback: fill, edge: edge)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .animation(.smooth(duration: 0.25), value: answered)
    }

    private func pick(_ o: Card, in q: Question) {
        guard chosen == nil else { return }
        chosen = o
        let ok = o == q.card
        if ok { right += 1 } else { wrong += 1 }
        if let a = q.card.a, q.kind != .listen { Player.shared.play(Audio.wordPath(a)) }
        if store.answer(q.card, correct: ok, goal: goal) {
            learned.append(q.card)
            // learned: drop its remaining questions
            let rest = queue[(idx + 1)...].filter { $0.card != q.card }
            queue = Array(queue[...idx]) + rest
        } else if !ok && !retried.contains(q.card.k) {
            // ask once more later, in another way
            retried.insert(q.card.k)
            let other = kinds(for: q.card).filter { $0 != q.kind }.randomElement() ?? q.kind
            queue.append(make(q.card, other))
        }
    }

    private func feedback(_ q: Question, picked: Card) -> some View {
        let ok = picked == q.card
        let c = q.card
        return VStack(alignment: .leading, spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ok ? (learned.contains(c) ? "答對了！學會了 🎉" : "答對了！") : "答錯了")
                        .font(.headline).foregroundStyle(ok ? T.greenInk : T.rustInk)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(c.h).font(.title.weight(.medium)).foregroundStyle(T.blueInk)
                        Text(store.cardRom(c, rom, place)).font(T.lat(20)).foregroundStyle(T.greenInk)
                        Text(store.cardZy(c, place)).foregroundStyle(T.purpleInk)
                        Spacer()
                        if let a = c.a { PlayButton(path: Audio.wordPath(a), size: 34) }
                    }
                    Text(c.firstMeaning).foregroundStyle(T.glyph)
                    if q.kind == .fillBlank, let x = q.example {
                        Text(x.h).foregroundStyle(T.blueInk).padding(.top, 4)
                        Text(store.exampleRom(c, x, rom, place)).font(T.lat(15)).foregroundStyle(T.greenInk)
                    }
                }
            }
            Button {
                chosen = nil
                idx += 1
            } label: {
                Text(idx + 1 >= queue.count ? "看結果" : "下一題").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .prominentButton(T.greenEdge)
        }
    }

    // MARK: end

    private var summary: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("練習完了").font(.largeTitle.weight(.bold)).foregroundStyle(T.glyph)
                Text("答對 \(right) 題，答錯 \(wrong) 題").foregroundStyle(T.muted)
                if !learned.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("學會了，移到「熟悉」：").font(.headline).foregroundStyle(T.greenInk)
                            ForEach(learned) { WordRow(card: $0) }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button { start() } label: { Text("再練一次").frame(maxWidth: .infinity, minHeight: 40) }
                        .softButton()
                        .disabled(store.unknownCount == 0)
                    Button { dismiss() } label: { Text("完成").frame(maxWidth: .infinity, minHeight: 40) }
                        .prominentButton(T.greenEdge)
                }
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}
