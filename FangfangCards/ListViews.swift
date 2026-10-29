import SwiftUI

private func matches(_ c: Card, _ q: String) -> Bool {
    if q.isEmpty { return true }
    let l = q.lowercased()
    return c.h.contains(q) || c.r.contains { $0.lowercased().contains(l) } || c.d.contains { $0.t.contains(q) }
}

/// 不熟: the words you swiped left. Study them here.
struct UnknownView: View {
    @EnvironmentObject var store: Store
    @AppStorage("goal") private var goal = 3
    @State private var studying = false
    @State private var toning = false
    @State private var blanks = false
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        let list = store.unknownCards.filter { matches($0, query) }
        List {
            Section {
                Button { studying = true } label: {
                    Label("開始練習", systemImage: "graduationcap.fill")
                        .ffFont(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .prominentButton(T.greenEdge)
                .disabled(store.unknownCount == 0)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                Button { blanks = true } label: {
                    Label("例句填空", systemImage: "text.badge.checkmark")
                        .ffFont(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .softButton()
                .disabled(!store.unknownCards.contains { !$0.blankExamples.isEmpty })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                Button { toning = true } label: {
                    Label("聲調練習", systemImage: "waveform")
                        .ffFont(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .softButton()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
            } footer: {
                Text("練習時連續答對 \(goal) 次，詞就會移到「熟悉」。往右滑可以直接移過去。例句填空：只做例句填空題。聲調練習：聽發音，選出聲調正確的拼法（先用不熟的詞，再用常用詞）。")
            }
            Section("不熟的詞（\(store.unknownCount)）") {
                if list.isEmpty {
                    Text(query.isEmpty ? "在「新詞」往左滑的詞會出現在這裡。" : "找不到。")
                        .foregroundStyle(T.muted)
                }
                ForEach(list) { c in
                    Button { detail = c } label: { WordRow(card: c, streak: store.streak(c), goal: goal) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button { store.mark(c, known: true, undoable: false) } label: { Label("熟悉", systemImage: "checkmark") }
                                .tint(T.greenEdge)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.forget(c) } label: { Label("移回新詞", systemImage: "arrow.uturn.backward") }
                                .tint(T.oliveEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .searchable(text: $query, prompt: "漢字、羅馬字或意思")

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .fullScreenCover(isPresented: $studying) { StudyView().environmentObject(store) }
        .fullScreenCover(isPresented: $blanks) { StudyView(blanksOnly: true).environmentObject(store) }
        .fullScreenCover(isPresented: $toning) { ToneView().environmentObject(store) }
    }
}

/// 熟悉: known words. Review them as cards; swiping left sends a word back to 不熟.
struct KnownView: View {
    @EnvironmentObject var store: Store
    @State private var mode = 0
    @State private var reviewKeys: [String] = []
    @State private var pos = 0
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("卡片複習").tag(0)
                Text("列表").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            if mode == 0 { review } else { list }
        }
        .appBackground()

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .onAppear { if reviewKeys.isEmpty { shuffle() } }
    }

    private var reviewCards: [Card] {
        guard pos < reviewKeys.count else { return [] }
        var out: [Card] = []
        for k in reviewKeys[pos...] {
            if let c = store.byKey[k], store.status(c) == 1 { out.append(c) }
            if out.count == 4 { break }
        }
        return out
    }

    private var review: some View {
        let cards = reviewCards
        return VStack(spacing: 14) {
            Text(store.knownCount == 0 ? "" : "\(min(pos, reviewKeys.count)) / \(reviewKeys.count)")
                .ffFont(.footnote).foregroundStyle(T.muted)
            if cards.isEmpty {
                Spacer()
                Text(store.knownCount == 0 ? "在「新詞」往右滑的詞會出現在這裡。" : "這一輪複習完了！")
                    .foregroundStyle(T.muted)
                if store.knownCount > 0 {
                    Button("再複習一輪") { shuffle() }.prominentButton(T.greenEdge)
                }
                Spacer()
            } else {
                DeckArea(cards: cards, leftLabel: "不熟", rightLabel: "記得") { card, right in
                    if !right { store.mark(card, known: false, undoable: false) }
                    advance(past: card)
                }
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        let cards = store.knownCards.filter { matches($0, query) }
        return List {
            Section("熟悉的詞（\(store.knownCount)）") {
                ForEach(cards) { c in
                    Button { detail = c } label: { WordRow(card: c) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { store.mark(c, known: false, undoable: false) } label: { Label("不熟", systemImage: "xmark") }
                                .tint(T.rustEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: "漢字、羅馬字或意思")
    }

    private func shuffle() {
        reviewKeys = store.knownCards.map(\.k).shuffled()
        pos = 0
    }

    private func advance(past card: Card) {
        if let i = reviewKeys[pos...].firstIndex(of: card.k) { pos = i + 1 } else { pos += 1 }
    }
}
