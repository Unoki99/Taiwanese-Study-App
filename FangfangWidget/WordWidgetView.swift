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

    /// "rrggbb" → colour
    static func color(_ hex: String) -> Color {
        let v = UInt32(hex, radix: 16) ?? 0xf2f2f2
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    /// coloured pieces as one text; pieces without a colour (and texts from before colours) get `ink`
    static func attributed(_ segs: [WSeg]?, _ plain: String, ink: Color) -> AttributedString {
        guard let segs, !segs.isEmpty else { var a = AttributedString(plain); a.foregroundColor = ink; return a }
        var out = AttributedString()
        for s in segs {
            var a = AttributedString(s.t)
            a.foregroundColor = s.c.map(color) ?? ink
            out += a
        }
        return out
    }
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
        .containerBackground(for: .widget) { background }
    }

    // MARK: look: dark glass with an edge in the word's tone colours

    /// the colours of the word's syllables, in order (for the edge and the soft light in the corner)
    private var toneColors: [Color] {
        var out: [Color] = [], seen = Set<String>()
        for s in entry.word?.hc ?? [] { if let c = s.c, seen.insert(c).inserted { out.append(WT.color(c)) } }
        if out.isEmpty { return [WT.fnEdge, WT.fnEdge] }
        return out.count == 1 ? [out[0], out[0]] : out
    }

    private var background: some View {
        let cs = toneColors
        // see-through: a dark tint over the wallpaper (iOS 26 shows what's behind a widget's background
        // when it isn't solid); how dark is set in the app (設定 → 小工具 → 背景)
        let a = min(max(entry.bg, 0), 1)
        return ZStack {
            LinearGradient(colors: [Color(red: 0.15, green: 0.15, blue: 0.17).opacity(a), Color(red: 0.085, green: 0.085, blue: 0.095).opacity(min(1, a + 0.1))],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // a soft light from the word's first tone colour, top left, and the last one bottom right
            RadialGradient(colors: [cs.first!.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 230)
            RadialGradient(colors: [cs.last!.opacity(0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 230)
            // a glassy shine along the top
            LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
            ContainerRelativeShape()
                .strokeBorder(LinearGradient(colors: cs, startPoint: .leading, endPoint: .trailing), lineWidth: 2)
                .opacity(0.85)
        }
    }

    private func rom(_ xs: [String]) -> String { xs[min(max(entry.rom, 0), xs.count - 1)] }
    private func romC(_ xs: [[WSeg]]?) -> [WSeg]? { xs.map { $0[min(max(entry.rom, 0), $0.count - 1)] } }

    /// text in its colours (tone colours from the app), with a soft glow when it has any
    @ViewBuilder
    private func colored(_ segs: [WSeg]?, _ plain: String, ink: Color, font: Font, lines: Int = 1, scale: CGFloat = 0.6) -> some View {
        let t = Text(WT.attributed(segs, plain, ink: ink)).font(font)
        let glow = segs?.contains { $0.c != nil } ?? false
        ZStack(alignment: .leading) {
            if glow { t.blur(radius: 4).opacity(0.75).lineLimit(lines).minimumScaleFactor(scale) }
            t.lineLimit(lines).minimumScaleFactor(scale)
        }
        .shadow(color: .black.opacity(entry.bg < 0.7 ? 0.55 : 0), radius: 2, y: 1)
    }

    // MARK: 4×4

    private func large(_ w: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.categoryName).font(.caption2.weight(.bold)).foregroundStyle(WT.oliveInk)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(WT.olive.opacity(0.8)))
                Spacer()
                buttons(w, size: 34)
            }
            colored(w.hc, w.h, ink: WT.blueInk, font: .system(size: 40, weight: .semibold), scale: 0.5)
            colored(romC(w.rc), rom(w.r), ink: WT.greenInk, font: WT.lat(20))
            colored(w.zc, w.z, ink: WT.purpleInk, font: .system(size: 15))
            meaning(w, size: 15, lines: 3)
            Spacer(minLength: 0)
            if let xh = w.xh {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top) {
                        colored(w.xhc, xh, ink: WT.glyph, font: .system(size: 16), lines: 2, scale: 0.8)
                        Spacer(minLength: 4)
                        if let n = w.xn { roundButton(intent: PlayWidgetAudioIntent(path: WidgetShared.examplePath(n)),
                                                      icon: "play.fill", fill: Color.white.opacity(0.10), edge: Color.white.opacity(0.18), ink: WT.glyph, size: 28) }
                    }
                    if let xr = w.xr { colored(romC(w.xrc), rom(xr), ink: WT.greenInk, font: WT.lat(13), lines: 2, scale: 0.8) }
                    if let xz = w.xz { Text(xz).font(.system(size: 12)).foregroundStyle(WT.muted).lineLimit(2) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.18 * (1 - entry.bg))).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06))))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    // MARK: 4×2

    private func medium(_ w: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    colored(w.hc, w.h, ink: WT.blueInk, font: .system(size: 26, weight: .semibold), scale: 0.5)
                    colored(romC(w.rc), rom(w.r), ink: WT.greenInk, font: WT.lat(14))
                }
                Spacer(minLength: 4)
                buttons(w, size: 30)
            }
            meaning(w, size: 13, lines: 1)
            if let xh = w.xh {
                colored(w.xhc, xh, ink: WT.glyph, font: .system(size: 13), scale: 0.8)
                if let xr = w.xr { colored(romC(w.xrc), rom(xr), ink: WT.greenInk, font: WT.lat(11), scale: 0.8) }
                if let xz = w.xz { Text(xz).font(.system(size: 11)).foregroundStyle(WT.muted).lineLimit(1).minimumScaleFactor(0.8) }
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
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            }
            Text(w.m).font(.system(size: size)).foregroundStyle(WT.glyph).lineLimit(lines)
        }
    }

    /// ▶ the word, 收藏, ✓, → another word (glassy; 收藏 and ✓ get their colour when they're on)
    private func buttons(_ w: WidgetWord, size: CGFloat) -> some View {
        let glass = Color.white.opacity(0.10), glassEdge = Color.white.opacity(0.18)
        return HStack(spacing: 6) {
            if let a = w.a {
                roundButton(intent: PlayWidgetAudioIntent(path: WidgetShared.wordPath(a)),
                            icon: "play.fill", fill: glass, edge: glassEdge, ink: WT.glyph, size: size)
            }
            roundButton(intent: ToggleWidgetSaveIntent(key: w.k),
                        icon: entry.saved ? "bookmark.fill" : "bookmark",
                        fill: entry.saved ? WT.olive : glass, edge: entry.saved ? WT.oliveEdge : glassEdge,
                        ink: entry.saved ? WT.oliveInk : WT.glyph, size: size)
            roundButton(intent: MarkWidgetKnownIntent(key: w.k), icon: "checkmark",
                        fill: entry.known ? WT.pink : glass, edge: entry.known ? WT.pinkEdge : glassEdge,
                        ink: entry.known ? WT.pinkInk : WT.glyph, size: size)
            roundButton(intent: NextWidgetWordIntent(category: entry.category),
                        icon: "arrow.right", fill: glass, edge: glassEdge, ink: WT.glyph, size: size)
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
