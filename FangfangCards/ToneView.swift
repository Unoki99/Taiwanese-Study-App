import SwiftUI

/// one spelling of a word, differing only in the tone of its last syllable
struct ToneOption: Identifiable, Equatable {
    let id: String        // code of the last syllable, e.g. "ciD8"
    let tone: Int
    let rom: [String]     // 皓羅, 台羅, 白話字
}

struct ToneQuestion: Identifiable {
    let id = UUID()
    let card: Card
    let options: [ToneOption]
    let answer: ToneOption
}

let TONE_NAMES: [Int: String] = [1: "陰平", 2: "陰上", 3: "陰去", 4: "陰入", 5: "陽平", 7: "陽去", 8: "陽入"]

extension Store {
    /// every tone of the word's last syllable that exists, same letters otherwise
    func toneOptions(_ c: Card) -> (all: [ToneOption], answer: ToneOption)? {
        guard let codes = c.c, let last = codes.last, let d = last.last, let tone = Int(String(d)) else { return nil }
        let base = String(last.dropLast())
        let prefix = codes.dropLast().map { syl[$0] ?? ["", "", ""] }
        var all: [ToneOption] = []
        var answer: ToneOption?
        for t in [1, 2, 3, 4, 5, 7, 8] {
            let code = base + String(t)
            guard let s = syl[code], s.count == 3 else { continue }
            let rom = (0..<3).map { i in (prefix.map { $0[i] } + [s[i]]).joined(separator: "-") }
            let o = ToneOption(id: code, tone: t, rom: rom)
            all.append(o)
            if t == tone { answer = o }
        }
        guard let answer, all.count >= 2 else { return nil }
        return (all, answer)
    }

    func toneQuestion(_ c: Card, rom: Int) -> ToneQuestion? {
        guard c.a != nil, let r = toneOptions(c) else { return nil }
        let all = r.all, answer = r.answer
        // always include the look-alike: 皓羅 1↔8, 3↔4; 台羅/白話字 1↔4 (no mark)
        let pairs: [Int: Int] = rom == 0 ? [1: 8, 8: 1, 3: 4, 4: 3] : [1: 4, 4: 1]
        var pick = [answer]
        if let p = pairs[answer.tone], let twin = all.first(where: { $0.tone == p }) { pick.append(twin) }
        for o in all.shuffled() where pick.count < 4 && !pick.contains(o) { pick.append(o) }
        return ToneQuestion(card: c, options: pick.shuffled(), answer: answer)
    }
}

/// 聲調練習: hear the word, see the 漢字, pick the spelling with the right tone.
struct ToneView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0

    @State private var queue: [ToneQuestion] = []
    @State private var idx = 0
    @State private var chosen: ToneOption?
    @State private var right = 0
    @State private var wrong = 0

    private let roundSize = 15

    var body: some View {
        NavigationStack {
            Group {
                if queue.isEmpty {
                    ProgressView()
                } else if idx >= queue.count {
                    summary
                } else {
                    question(queue[idx])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("聲調練習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("結束")
                }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
        .onAppear { if queue.isEmpty { start() } }
    }

    // unknown words first, then common words
    private func start() {
        var words = store.unknownCards.shuffled()
        let seen = Set(words.map(\.k))
        words += store.cards.prefix(1500).filter { !seen.contains($0.k) }.shuffled()
        var qs: [ToneQuestion] = []
        for c in words {
            if let q = store.toneQuestion(c, rom: rom) { qs.append(q) }
            if qs.count == roundSize { break }
        }
        queue = qs
        idx = 0; chosen = nil; right = 0; wrong = 0
    }

    private func question(_ q: ToneQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("\(idx + 1) / \(queue.count)").ffFont(.footnote).foregroundStyle(T.muted)
                    Spacer()
                    Text("答對 \(right)").ffFont(.footnote).foregroundStyle(T.greenInk)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("聽發音，選出正確的拼法").ffFont(.subheadline, .bold).foregroundStyle(T.oliveInk)
                        HStack {
                            Text(q.card.h).scaledFont(56, weight: .medium).foregroundStyle(T.blueInk)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Spacer()
                            if let a = q.card.a { PlayButton(path: Audio.wordPath(a), size: 60) }
                        }
                        if q.card.syllables > 1 {
                            Text("只有最後一個字的聲調不一樣（前面的字唸起來會變調）")
                                .ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                }
                VStack(spacing: 12) {
                    ForEach(q.options) { o in
                        Button { pick(o, q) } label: { optionLabel(o, q) }
                            .buttonStyle(.plain)
                            .disabled(chosen != nil)
                    }
                }
                if chosen != nil { feedback(q) }
                rule
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task(id: q.id) {
            if let a = q.card.a { Player.shared.play(Audio.wordPath(a)) }
        }
    }

    private func optionLabel(_ o: ToneOption, _ q: ToneQuestion) -> some View {
        let answered = chosen != nil
        let isRight = o == q.answer
        let isPicked = chosen == o
        return HStack {
            Text(o.rom[min(max(rom, 0), 2)]).latFont(28).foregroundStyle(T.greenInk)
            Spacer()
            if answered {
                Text("\(o.tone)　\(TONE_NAMES[o.tone] ?? "")")
                    .ffFont(.subheadline, .bold)
                    .foregroundStyle(isRight ? T.greenInk : (isPicked ? T.rustInk : T.muted))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60)
        .glassSurface(RoundedRectangle(cornerRadius: 18),
                      tint: answered && isRight ? T.greenEdge.opacity(0.75)
                          : (answered && isPicked ? T.rustEdge.opacity(0.75) : T.key.opacity(0.35)),
                      interactive: !answered,
                      fallback: answered && isRight ? T.green : (answered && isPicked ? T.rust : T.key),
                      edge: answered && isRight ? T.greenEdge : (answered && isPicked ? T.rustEdge : T.keyEdge))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private func pick(_ o: ToneOption, _ q: ToneQuestion) {
        guard chosen == nil else { return }
        chosen = o
        if o == q.answer { right += 1 } else {
            wrong += 1
            // ask this word again at the end of the round
            if let again = store.toneQuestion(q.card, rom: rom) { queue.append(again) }
        }
    }

    private func feedback(_ q: ToneQuestion) -> some View {
        let ok = chosen == q.answer
        let t = q.answer.tone
        return VStack(alignment: .leading, spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ok ? "答對了！" : "答錯了").ffFont(.headline).foregroundStyle(ok ? T.greenInk : T.rustInk)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(q.card.h).ffFont(.title2, .medium).foregroundStyle(T.blueInk)
                        Text(q.answer.rom[min(max(rom, 0), 2)]).latFont(22).foregroundStyle(T.greenInk)
                        Text(q.card.z).foregroundStyle(T.purpleInk)
                    }
                    Text("第 \(t) 聲（\(TONE_NAMES[t] ?? "")）\(hint(t))").ffFont(.subheadline).foregroundStyle(T.glyph)
                    Text(q.card.firstMeaning).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
            Button {
                chosen = nil
                idx += 1
            } label: {
                Text(idx + 1 >= queue.count ? "看結果" : "下一題").ffFont(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .prominentButton(T.greenEdge)
        }
    }

    private func hint(_ t: Int) -> String {
        if rom == 0 {
            switch t {
            case 8: return "：記號跟第 1 聲一樣，但是結尾有 p／t／k／h"
            case 1: return "：記號跟第 8 聲一樣，但是結尾沒有 p／t／k／h"
            case 4: return "：記號跟第 3 聲一樣，但是結尾有 p／t／k／h"
            case 3: return "：記號跟第 4 聲一樣，但是結尾沒有 p／t／k／h"
            default: return ""
            }
        } else {
            switch t {
            case 4: return "：跟第 1 聲一樣沒有記號，但是結尾有 p／t／k／h"
            case 1: return "：跟第 4 聲一樣沒有記號，但是結尾沒有 p／t／k／h"
            case 8: return "：結尾有 p／t／k／h"
            default: return ""
            }
        }
    }

    private var rule: some View {
        Text(rom == 0
             ? "皓羅：第 1 聲和第 8 聲記號一樣，第 3 聲和第 4 聲記號一樣；第 4、8 聲結尾有 p／t／k／h。"
             : "台羅／白話字：第 1 聲和第 4 聲都沒有記號；第 4、8 聲結尾有 p／t／k／h。")
            .ffFont(.caption).foregroundStyle(T.muted)
            .padding(.top, 6)
    }

    private var summary: some View {
        VStack(spacing: 18) {
            Text("練習完了").ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
            Text("答對 \(right) 題，答錯 \(wrong) 題").foregroundStyle(T.muted)
            HStack(spacing: 12) {
                Button { start() } label: { Text("再一輪").frame(maxWidth: .infinity, minHeight: 40) }
                    .softButton()
                Button { dismiss() } label: { Text("完成").frame(maxWidth: .infinity, minHeight: 40) }
                    .prominentButton(T.greenEdge)
            }
        }
        .padding()
        .frame(maxWidth: 560)
    }
}
