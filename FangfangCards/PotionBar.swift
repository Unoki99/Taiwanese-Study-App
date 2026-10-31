import SwiftUI

/// A glowing potion in a glass tube, as a progress bar (練習) or a score.
/// The liquid fills up to the score (with a little splash), its colour runs from purple and pink (odd)
/// through yellow to green and teal (normal), bubbles rise in it and its edge ripples.
struct PotionBar: View {
    let value: Double                  // 0–1
    var height: CGFloat = 30
    var showMarks = true               // two small notches at 4 % and 15 % (where a score turns 🤔 / ✅)
    var label = "通順程度"
    var palette: PotionPalette = .rainbow
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PotionLiquid(level: shown, moving: !reduceMotion, showMarks: showMarks, palette: palette)
            .frame(height: height)
            .padding(.vertical, 6)
            .onAppear {
                shown = 0
                withAnimation(.spring(response: 1.2, dampingFraction: 0.62).delay(0.1)) { shown = value }
            }
            .onChange(of: value) {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.62)) { shown = value }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

/// the tube itself; `level` animates (the spring above), the ripples and bubbles run on the clock
private struct PotionLiquid: View, Animatable {
    var level: Double
    let moving: Bool
    var showMarks = true
    var palette: PotionPalette = .rainbow
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    /// purple → pink → orange → yellow (🤔 starts at 4 %) → green (✅ from 15 %) → teal
    /// 排句子: deep blue → sky → ice
    static let blueGradient = Gradient(stops: [
        .init(color: Color(hex: 0x3a3fd8), location: 0),
        .init(color: Color(hex: 0x4f7dff), location: 0.35),
        .init(color: Color(hex: 0x6eaaff), location: 0.65),
        .init(color: Color(hex: 0x9ad8ff), location: 0.9),
        .init(color: Color(hex: 0xc9f2ff), location: 1.0),
    ])

    static let gradient = Gradient(stops: [
        .init(color: Color(hex: 0xa66bff), location: 0),
        .init(color: Color(hex: 0xff5c9a), location: 0.04),
        .init(color: Color(hex: 0xff9a4a), location: 0.10),
        .init(color: Color(hex: 0xffe066), location: 0.17),
        .init(color: Color(hex: 0x7ee081), location: 0.40),
        .init(color: Color(hex: 0x4fd8d0), location: 1.0),
    ])

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { tl in
            let t = moving ? tl.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                // glow: the liquid again, blurred, outside the glass
                liquid(t, bubbles: false)
                    .blur(radius: 9)
                    .opacity(0.8)
                    .allowsHitTesting(false)
                // inside the glass
                ZStack {
                    Capsule().fill(Color.black.opacity(0.35))
                    liquid(t, bubbles: true)
                    if showMarks { marks }
                }
                .clipShape(Capsule())
                // the glass: rim and a shine along the top
                Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                Capsule()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 7)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 3)
                    .allowsHitTesting(false)
            }
        }
    }

    /// where 🤔 and ✅ begin
    private var marks: some View {
        GeometryReader { g in
            ForEach([0.04, 0.15], id: \.self) { x in
                Rectangle().fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: g.size.height * 0.45)
                    .position(x: g.size.width * x, y: g.size.height * 0.78)
            }
        }
        .allowsHitTesting(false)
    }

    private func liquid(_ t: Double, bubbles: Bool) -> some View {
        let lvl = min(max(level, 0), 1.08)          // the spring can splash a little past the score
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            let edge = max(w * min(lvl, 1), lvl > 0.001 ? 10 : 0)   // always a drop, so 0 % still shows
            guard edge > 0 else { return }

            // the liquid, its right edge rippling
            var p = Path()
            p.move(to: .zero)
            let amp = edge >= w - 1 ? 0 : 3.0
            var y = 0.0
            while y <= h {
                let x = edge + sin(y / h * .pi * 2 + t * 3.2) * amp + sin(y / h * .pi * 5 - t * 4.7) * amp * 0.35
                p.addLine(to: CGPoint(x: x, y: y))
                y += 2
            }
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(palette == .blue ? PotionLiquid.blueGradient : PotionLiquid.gradient,
                                              startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))

            guard bubbles else { return }
            ctx.clip(to: p)
            // a lighter band at the top of the liquid, and a darker one at the bottom
            ctx.fill(Path(CGRect(x: 0, y: 0, width: edge + 6, height: h * 0.32)), with: .color(.white.opacity(0.16)))
            ctx.fill(Path(CGRect(x: 0, y: h * 0.72, width: edge + 6, height: h * 0.28)), with: .color(.black.opacity(0.14)))

            // bubbles rising (the same bubbles every time: positions come from their number)
            func frac(_ v: Double) -> Double { v - floor(v) }
            for i in 0..<18 {
                let s = Double(i)
                let fx = frac(sin(s * 12.9898) * 43758.5453)
                let fs = frac(sin(s * 78.233) * 12345.678)
                let speed = 0.18 + fs * 0.35
                let phase = frac(t * speed + fx * 3.1)
                let bx = 6 + fx * max(edge - 12, 1) + sin(t * 2 + s) * 1.5
                let by = h * (1.05 - phase * 1.1)
                let r = 1.0 + fs * 1.8
                let a = 0.6 * sin(phase * .pi)
                ctx.stroke(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                           with: .color(.white.opacity(a)), lineWidth: 0.8)
            }

            // a twinkle where the liquid ends
            if edge < w - 4 {
                let tw = 0.5 + 0.5 * sin(t * 5)
                let r = 2.0 + tw * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: edge - r - 2, y: h * 0.28 - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.45 + 0.4 * tw)))
            }
        }
    }
}

enum PotionPalette { case rainbow, blue }
