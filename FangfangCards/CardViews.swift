import SwiftUI

/// The big swipeable card: 漢字, romanization, 方音, audio, meanings and one example.
struct WordCard: View {
    let card: Card
    var isTop = true
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("hideMeaning") private var hideMeaning = false
    @State private var revealed = false
    @State private var showDetail = false
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.h)
                    .scaledFont(card.h.count > 3 ? 44 : 60, weight: .medium)
                    .foregroundStyle(T.blueInk)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer()
                CardChips(card: card, place: place)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.cardRom(card, rom, place)).font(T.lat(26)).foregroundStyle(T.greenInk)
                    Text(store.cardZy(card, place)).scaledFont(18).foregroundStyle(T.purpleInk)
                    if let x = store.alsoSaid(card, rom, place).first {
                        HStack(spacing: 6) {
                            Chip(text: "也講", fill: Color(hex: 0x4c3a5b), edge: Color(hex: 0x7b3c9b), ink: T.purpleInk)
                            Text(x.rom).font(T.lat(15)).foregroundStyle(T.greenInk.opacity(0.85))
                        }
                    } else if let o = card.o?.first {
                        HStack(spacing: 6) {
                            Chip(text: o.l)
                            Text(o.r[min(max(rom, 0), 2)]).font(T.lat(15)).foregroundStyle(T.greenInk.opacity(0.85))
                        }
                    }
                }
                Spacer()
                if let a = card.a { PlayButton(path: Audio.wordPath(a), size: 44, onCard: true) }
            }
            Rectangle().fill(T.fnEdge).frame(height: 2)

            if hideMeaning && !revealed {
                Spacer()
                Text("點一下看意思")
                    .font(.headline).foregroundStyle(T.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(card.d.prefix(3).enumerated()), id: \.offset) { i, d in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        NumBadge(n: i + 1)
                        if !d.p.isEmpty { Chip(text: d.p) }
                        Text(d.t).foregroundStyle(T.glyph).lineLimit(3)
                    }
                }
                if card.d.count > 3 {
                    Text("還有 \(card.d.count - 3) 個意思").font(.caption).foregroundStyle(T.muted)
                }
                if let x = card.firstExample {
                    HStack(alignment: .top, spacing: 10) {
                        PlayButton(path: Audio.examplePath(x.n), size: 28, onCard: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.exampleHan(card, x, place))
                            Text(store.exampleRom(card, x, rom, place)).font(T.lat(15)).foregroundStyle(T.greenInk)
                            Text(x.z).font(.footnote).foregroundStyle(T.muted)
                        }
                        .lineLimit(3)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                Button { showDetail = true } label: {
                    Label("詳細", systemImage: "text.book.closed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(T.greenInk)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)   // frosted, so it doesn't stretch while the card moves
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(CardSurface(frosted: isTop))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { revealed.toggle() }
        .sheet(isPresented: $showDetail) { CardDetail(card: card).environmentObject(store) }
    }
}

/// Green / rust glow from the side you swipe toward, plus a soft highlight under the finger.
/// Kept separate from WordCard so dragging only redraws this, not the whole card.
struct CardLight: View {
    let swipe: CGFloat        // -1 … 1
    let touch: CGPoint?

    var body: some View {
        let color = swipe > 0 ? T.greenEdge : T.rustEdge
        let a = Double(min(abs(swipe), 1))
        return GeometryReader { g in
            ZStack {
                if a > 0.02 {
                    LinearGradient(colors: [color.opacity(0.55 * a), color.opacity(0)],
                                   startPoint: swipe > 0 ? .trailing : .leading,
                                   endPoint: swipe > 0 ? .leading : .trailing)
                    RoundedRectangle(cornerRadius: 28).strokeBorder(color.opacity(0.9 * a), lineWidth: 3)
                }
                if let p = touch, g.size.width > 0, g.size.height > 0 {
                    RadialGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                   center: UnitPoint(x: p.x / g.size.width, y: p.y / g.size.height),
                                   startRadius: 0, endRadius: 200)
                        .blendMode(.plusLighter)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .allowsHitTesting(false)
    }
}

/// Everything about one word: all meanings and all examples.
struct CardDetail: View {
    let card: Card
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(card.h).scaledFont(44, weight: .medium).foregroundStyle(T.blueInk)
                                Spacer()
                                CardChips(card: card, place: place)
                                if let a = card.a { PlayButton(path: Audio.wordPath(a), size: 40) }
                            }
                            Text(store.cardRom(card, rom, place)).font(T.lat(24)).foregroundStyle(T.greenInk)
                            Text(store.cardZy(card, place)).scaledFont(17).foregroundStyle(T.purpleInk)
                            // other readings, and the 通行 one when a place is shown
                            ForEach(Array(store.alsoSaid(card, rom, place).enumerated()), id: \.offset) { _, x in
                                OtherRow(label: "也講", rom: x.rom, zy: x.zy)
                            }
                            if card.differs(in: place), !store.alsoSaid(card, rom, place).contains(where: { $0.rom == card.rom(rom) }) {
                                OtherRow(label: "通行", rom: card.rom(rom), zy: card.z)
                            }
                            ForEach(Array((card.o ?? []).enumerated()), id: \.offset) { _, o in
                                OtherRow(label: o.l, rom: o.r[min(max(rom, 0), 2)], zy: o.z)
                            }
                            if let cs = card.cats, !cs.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(cs, id: \.self) { i in
                                        if let t = store.topics.first(where: { $0.id == i }) { Chip(text: t.name, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                                    }
                                }
                                .padding(.top, 2)
                            }
                            Text(statusText).font(.caption).foregroundStyle(T.muted).padding(.top, 4)
                        }
                    }
                    ForEach(Array(card.d.enumerated()), id: \.offset) { i, d in
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    NumBadge(n: i + 1)
                                    if !d.p.isEmpty { Chip(text: d.p) }
                                    Text(d.t).foregroundStyle(T.glyph)
                                }
                                LinkRows(sy: d.sy, an: d.an)
                                ForEach(Array(d.x.enumerated()), id: \.offset) { _, x in
                                    HStack(alignment: .top, spacing: 10) {
                                        PlayButton(path: Audio.examplePath(x.n), size: 28)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(store.exampleHan(card, x, place))
                                            Text(store.exampleRom(card, x, rom, place)).font(T.lat(15)).foregroundStyle(T.greenInk)
                                            Text(x.z).font(.footnote).foregroundStyle(T.muted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if store.cardHasGuess(card, place) { GuessNote() }
                    if card.sy != nil || card.an != nil {
                        Panel { LinkRows(sy: card.sy, an: card.an) }
                    }
                    if card.t == "臺華共同" {
                        Text("臺華共同詞：意思跟華語一樣。").font(.footnote).foregroundStyle(T.muted)
                    }
                    HStack(spacing: 12) {
                        Button { store.mark(card, known: false, undoable: false); dismiss() } label: {
                            Label("不熟", systemImage: "xmark").frame(maxWidth: .infinity)
                        }
                        .prominentButton(T.rustEdge)
                        Button { store.mark(card, known: true, undoable: false); dismiss() } label: {
                            Label("熟悉", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .prominentButton(T.greenEdge)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(card.h)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { RomButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private var statusText: String {
        switch store.status(card) {
        case 1?: return "熟悉"
        case 2?: return "不熟（連續答對 \(store.streak(card)) 次）"
        default: return "還沒看過"
        }
    }
}

/// One row in the 不熟 / 熟悉 lists.
struct WordRow: View {
    let card: Card
    @EnvironmentObject var store: Store
    var streak: Int? = nil
    var goal: Int = 3
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.h).font(.title3.weight(.medium)).foregroundStyle(T.blueInk)
                    Text(store.cardRom(card, rom, place)).font(T.lat(16)).foregroundStyle(T.greenInk)
                    Text(store.cardZy(card, place)).font(.footnote).foregroundStyle(T.purpleInk)
                }
                Text(card.firstMeaning).font(.footnote).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer()
            if let s = streak {
                HStack(spacing: 3) {
                    ForEach(0..<goal, id: \.self) { i in
                        Circle().fill(i < s ? T.greenInk : T.fnEdge).frame(width: 7, height: 7)
                    }
                }
                .accessibilityLabel("答對 \(s) 次")
            }
        }
        .padding(.vertical, 2)
    }
}


/// 白/文/俗, 替, 臺華共同, and the place when its reading is shown
struct CardChips: View {
    let card: Card
    let place: Int
    @EnvironmentObject var store: Store
    var body: some View {
        HStack(spacing: 4) {
            RegChip(reg: card.g)
            if card.s == 1 { Chip(text: "替", fill: T.rust, edge: T.rustEdge, ink: T.rustInk) }
            if let t = card.t { Chip(text: t, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
            if card.differs(in: place), place < store.places.count {
                Chip(text: String(store.places[place].prefix(2)), fill: Color(hex: 0x4c3a5b), edge: Color(hex: 0x7b3c9b), ink: T.purpleInk)
                if store.isGuessed(card, place) { Chip(text: "推測", fill: T.fn, edge: T.fnEdge, ink: T.muted) }
            }
        }
    }
}

struct OtherRow: View {
    let label: String
    let rom: String
    let zy: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Chip(text: label)
            Text(rom).font(T.lat(17)).foregroundStyle(T.greenInk)
            Text(zy).font(.footnote).foregroundStyle(T.purpleInk)
        }
    }
}

/// 近義 / 反義 words
struct LinkRows: View {
    let sy: [[String]]?
    let an: [[String]]?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("近", sy)
            row("反", an)
        }
    }
    @ViewBuilder private func row(_ name: String, _ list: [[String]]?) -> some View {
        if let list, !list.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Chip(text: name, fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
                Text(list.map { $0.count > 1 && !$0[1].isEmpty ? "\($0[0]) \($0[1])" : $0[0] }.joined(separator: "、"))
                    .font(.footnote).foregroundStyle(T.glyph.opacity(0.85))
            }
        }
    }
}
