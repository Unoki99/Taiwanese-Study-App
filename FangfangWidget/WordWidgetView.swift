import WidgetKit
import SwiftUI
import AppIntents

/// the app's colours (same as Theme.swift)
enum WT {
    static let bg = Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255)
    static let fn = Color(red: 0x2b / 255, green: 0x2b / 255, blue: 0x2d / 255)
    static let fnEdge = Color(red: 0x4b / 255, green: 0x4b / 255, blue: 0x4e / 255)
    static let glyph = Color(red: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf2 / 255)
    static let muted = Color(red: 0xa3 / 255, green: 0xa3 / 255, blue: 0xa8 / 255)
    static let blueInk = Color(red: 0xc8 / 255, green: 0xcf / 255, blue: 0xff / 255)
    static let green = Color(red: 0x44 / 255, green: 0x50 / 255, blue: 0x3a / 255)
    static let greenEdge = Color(red: 0x4f / 255, green: 0x6c / 255, blue: 0x32 / 255)
    static let greenInk = Color(red: 0xd4 / 255, green: 0xef / 255, blue: 0xc0 / 255)
    static let purpleInk = Color(red: 0xe3 / 255, green: 0xc6 / 255, blue: 0xf7 / 255)
    static let olive = Color(red: 0x5a / 255, green: 0x52 / 255, blue: 0x38 / 255)
    static let oliveEdge = Color(red: 0x8c / 255, green: 0x7a / 255, blue: 0x38 / 255)
    static let oliveInk = Color(red: 0xf1 / 255, green: 0xe3 / 255, blue: 0xae / 255)
    static let pink = Color(red: 0x5e / 255, green: 0x3a / 255, blue: 0x4f / 255)
    static let pinkEdge = Color(red: 0xa0 / 255, green: 0x4a / 255, blue: 0x78 / 255)
    static let pinkInk = Color(red: 0xf8 / 255, green: 0xcb / 255, blue: 0xe2 / 255)
    static func lat(_ size: CGFloat) -> Font { .custom("DejaVuSans", size: size) }
}

struct WordWidgetView: View {
    let entry: WordEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let w = entry.word {
                if family == .systemLarge { large(w) } else { medium(w) }
            } else {
                VStack(spacing: 6) {
                    Text("方方詞卡").font(.headline).foregroundStyle(WT.glyph)
                    Text(entry.empty ?? "").font(.footnote).foregroundStyle(WT.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) { WT.bg }
    }

    private func rom(_ xs: [String]) -> String { xs[min(max(entry.rom, 0), xs.count - 1)] }

    // MARK: 4×4

    private func large(_ w: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.categoryName).font(.caption2.weight(.bold)).foregroundStyle(WT.oliveInk)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(WT.olive))
                Spacer()
                buttons(w, size: 34)
            }
            Text(w.h).font(.system(size: 40, weight: .semibold)).foregroundStyle(WT.blueInk)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(rom(w.r)).font(WT.lat(20)).foregroundStyle(WT.greenInk).lineLimit(1).minimumScaleFactor(0.6)
            Text(w.z).font(.system(size: 15)).foregroundStyle(WT.purpleInk).lineLimit(1)
            meaning(w, size: 15, lines: 3)
            Spacer(minLength: 0)
            if let xh = w.xh {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top) {
                        Text(xh).font(.system(size: 16)).foregroundStyle(WT.glyph).lineLimit(2)
                        Spacer(minLength: 4)
                        if let n = w.xn { roundButton(intent: PlayWidgetAudioIntent(path: WidgetShared.examplePath(n)),
                                                      icon: "play.fill", fill: WT.green, edge: WT.greenEdge, ink: WT.greenInk, size: 28) }
                    }
                    if let xr = w.xr { Text(rom(xr)).font(WT.lat(13)).foregroundStyle(WT.greenInk).lineLimit(2) }
                    if let xz = w.xz { Text(xz).font(.system(size: 12)).foregroundStyle(WT.muted).lineLimit(2) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(WT.fn))
            }
        }
    }

    // MARK: 4×2

    private func medium(_ w: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(w.h).font(.system(size: 26, weight: .semibold)).foregroundStyle(WT.blueInk)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(rom(w.r)).font(WT.lat(14)).foregroundStyle(WT.greenInk).lineLimit(1).minimumScaleFactor(0.6)
                    Text(w.z).font(.system(size: 12)).foregroundStyle(WT.purpleInk).lineLimit(1)
                }
                Spacer(minLength: 4)
                buttons(w, size: 30)
            }
            meaning(w, size: 13, lines: 2)
            if let xh = w.xh {
                Text(xh).font(.system(size: 13)).foregroundStyle(WT.glyph).lineLimit(1)
                if let xr = w.xr { Text(rom(xr)).font(WT.lat(11)).foregroundStyle(WT.greenInk).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: parts

    private func meaning(_ w: WidgetWord, size: CGFloat, lines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !w.p.isEmpty {
                Text(w.p).font(.system(size: size - 3, weight: .bold)).foregroundStyle(WT.muted)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(WT.fn))
            }
            Text(w.m).font(.system(size: size)).foregroundStyle(WT.glyph).lineLimit(lines)
        }
    }

    /// ▶ the word, 收藏, → another word
    private func buttons(_ w: WidgetWord, size: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let a = w.a {
                roundButton(intent: PlayWidgetAudioIntent(path: WidgetShared.wordPath(a)),
                            icon: "play.fill", fill: WT.green, edge: WT.greenEdge, ink: WT.greenInk, size: size)
            }
            roundButton(intent: ToggleWidgetSaveIntent(key: w.k),
                        icon: entry.saved ? "bookmark.fill" : "bookmark",
                        fill: entry.saved ? WT.olive : WT.fn, edge: entry.saved ? WT.oliveEdge : WT.fnEdge,
                        ink: entry.saved ? WT.oliveInk : WT.glyph, size: size)
            roundButton(intent: MarkWidgetKnownIntent(key: w.k), icon: "checkmark",
                        fill: entry.known ? WT.pink : WT.fn, edge: entry.known ? WT.pinkEdge : WT.fnEdge,
                        ink: entry.known ? WT.pinkInk : WT.glyph, size: size)
            roundButton(intent: NextWidgetWordIntent(category: entry.category),
                        icon: "arrow.right", fill: WT.fn, edge: WT.fnEdge, ink: WT.glyph, size: size)
        }
    }

    private func roundButton<I: AppIntent>(intent: I, icon: String, fill: Color, edge: Color, ink: Color, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().stroke(edge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
