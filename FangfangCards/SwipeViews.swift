import SwiftUI

/// A stack of cards: drag right = 認識 (known), drag left = 不熟 (unknown).
struct SwipeStack: View {
    let cards: [Card]                       // top card first
    let onSwipe: (Card, Bool) -> Void       // true = right (known)
    @State private var offset: CGSize = .zero
    @State private var flying = false
    @State private var touch: CGPoint?

    var body: some View {
        ZStack {
            ForEach(Array(cards.prefix(3).enumerated()).reversed(), id: \.element.id) { i, card in
                WordCard(card: card, isTop: i == 0)
                    .overlay {
                        if i == 0 { CardLight(swipe: max(-1, min(1, offset.width / 140)), touch: touch) }
                    }
                    .overlay(alignment: .top) { if i == 0 { stamp } }
                    .scaleEffect(i == 0 ? 1 : 1 - CGFloat(i) * 0.04)
                    .offset(y: CGFloat(i) * 14)
                    .offset(i == 0 ? offset : .zero)
                    .rotationEffect(.degrees(i == 0 ? Double(offset.width / 18) : 0))
                    .allowsHitTesting(i == 0 && !flying)
                    .gesture(drag(card))
                    .zIndex(Double(10 - i))
            }
        }
    }

    private var stamp: some View {
        let right = offset.width > 0
        let amount = min(abs(offset.width) / 110, 1)
        return Text(right ? "認識" : "不熟")
            .ffFont(.title, .heavy)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(right ? T.greenInk : T.rustInk)
            .background(RoundedRectangle(cornerRadius: 12).fill((right ? T.green : T.rust).opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(right ? T.greenEdge : T.rustEdge, lineWidth: 3))
            .rotationEffect(.degrees(right ? -10 : 10))
            .padding(.top, 24)
            .opacity(amount)
            .allowsHitTesting(false)
    }

    private func drag(_ card: Card) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in offset = v.translation; touch = v.location }
            .onEnded { v in
                withAnimation(.easeOut(duration: 0.3)) { touch = nil }
                let w = v.translation.width + v.predictedEndTranslation.width * 0.25
                if abs(w) > 120 { fly(card, right: w > 0) }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero } }
            }
    }

    private func fly(_ card: Card, right: Bool) {
        flying = true
        withAnimation(.easeIn(duration: 0.2)) {
            offset = CGSize(width: right ? 700 : -700, height: offset.height + 40)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                offset = .zero
                flying = false
                onSwipe(card, right)
            }
        }
    }
}

/// ✕ / ↺ / ✓ buttons under a stack
struct SwipeButtons: View {
    var leftLabel = "不熟"
    var rightLabel = "認識"
    var canUndo = false
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUndo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 22) {
            round("xmark", leftLabel, T.rust, T.rustEdge, T.rustInk, onLeft)
                .keyboardShortcut(.leftArrow, modifiers: [])
            if let onUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .scaledFont(18, weight: .bold)
                        .frame(width: 46, height: 46)
                        .foregroundStyle(canUndo ? T.oliveInk : T.fnEdge)
                        .glassSurface(Circle(), tint: T.fn.opacity(0.4), interactive: true)
                }
                .disabled(!canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("復原")
            }
            round("checkmark", rightLabel, T.green, T.greenEdge, T.greenInk, onRight)
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func round(_ icon: String, _ label: String, _ fill: Color, _ edge: Color, _ ink: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).scaledFont(22, weight: .heavy)
                Text(label).ffFont(.caption2, .bold)
            }
            .frame(width: 68, height: 68)
            .foregroundStyle(ink)
            .glassSurface(Circle(), tint: edge.opacity(0.55), interactive: true, fallback: fill, edge: edge)
        }
        .accessibilityLabel(label)
    }
}

/// 新詞: go through the dictionary, most common words first.
struct NewDeckView: View {
    @EnvironmentObject var store: Store
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("topic") private var topic = -1

    var body: some View {
        let queue = store.newQueue(4, topic: topic)
        VStack(spacing: 18) {
            Text("已看 \(store.seenCount) / \(store.cards.count)　熟悉 \(store.knownCount)　不熟 \(store.unknownCount)")
                .ffFont(.footnote).foregroundStyle(T.muted)
            if queue.isEmpty {
                Spacer()
                Text(topic < 0 ? "全部的詞都看過了！" : "這個主題的詞都看過了！").ffFont(.title3).foregroundStyle(T.muted)
                Spacer()
            } else {
                DeckArea(cards: queue) { card, right in
                    store.mark(card, known: right)
                } undo: {
                    store.undo()
                }
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .appBackground()
        .rootPage("新詞") {
            Menu {
                Picker("主題", selection: $topic) {
                    Text("全部（最常用的先）").tag(-1)
                    ForEach(store.topics) { t in Text("\(t.name)（\(t.count)）").tag(t.id) }
                }
            } label: {
                Label(topicName, systemImage: "square.stack.3d.up").labelStyle(.titleAndIcon)
                    .ffFont(.subheadline, .semibold)
            }
        }
        .onChange(of: queue.first?.k) { _, _ in
            if autoPlay, let a = queue.first?.a { Player.shared.play(Audio.wordPath(a)) }
        }
    }
}

extension NewDeckView {
    var topicName: String {
        store.topics.first(where: { $0.id == topic })?.name ?? "全部"
    }
}

/// a stack plus its buttons
struct DeckArea: View {
    let cards: [Card]
    var leftLabel = "不熟"
    var rightLabel = "認識"
    let onSwipe: (Card, Bool) -> Void
    var undo: (() -> Void)? = nil
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 18) {
            SwipeStack(cards: cards, onSwipe: onSwipe).frame(maxHeight: 680).frame(maxHeight: .infinity)
            if let top = cards.first {
                SwipeButtons(leftLabel: leftLabel, rightLabel: rightLabel, canUndo: store.canUndo,
                             onLeft: { onSwipe(top, false) },
                             onRight: { onSwipe(top, true) },
                             onUndo: undo)
            }
        }
    }
}
