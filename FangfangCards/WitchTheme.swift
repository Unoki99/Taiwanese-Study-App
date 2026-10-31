import SwiftUI

/// 女巫小屋: the background of every page. A dusky window-sky fading into warm, sooty wood; moonlight from the
/// top right and candlelight from the bottom left; a crescent moon and a few stars; a bundle of herbs drying
/// on a string; laurel and a little mushroom along the bottom; fireflies drifting slowly.
/// Everything is faint, so text stays easy to read, and nothing reacts to touch.
struct WitchBackground: View {
    @State private var drift = false

    // fixed places (as a share of the screen), so the stars and fireflies don't jump around
    private static let stars: [(x: CGFloat, y: CGFloat, s: CGFloat)] = [
        (0.62, 0.05, 9), (0.74, 0.12, 6), (0.55, 0.14, 5), (0.83, 0.20, 7), (0.70, 0.26, 4), (0.93, 0.31, 5),
    ]
    private static let flies: [(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat, t: Double)] = [
        (0.12, 0.62, 30, -24, 7.5), (0.30, 0.80, -26, -18, 9.0), (0.48, 0.70, 22, 26, 8.2), (0.70, 0.86, -30, -12, 10.5),
        (0.86, 0.66, 18, 30, 7.8), (0.22, 0.45, 24, 20, 11.0), (0.78, 0.48, -22, 18, 9.6), (0.58, 0.93, 26, -22, 8.8),
    ]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                // dusk sky at the top, warm wood and soot further down
                LinearGradient(colors: [Color(hex: 0x231b29), Color(hex: 0x1e1815), Color(hex: 0x16110d)],
                               startPoint: .top, endPoint: .bottom)
                // moonlight and candlelight
                RadialGradient(colors: [Color(hex: 0xcfc6ff).opacity(0.13), .clear],
                               center: UnitPoint(x: 0.92, y: 0.04), startRadius: 0, endRadius: max(w, 300) * 0.75)
                RadialGradient(colors: [Color(hex: 0xffae55).opacity(0.17), .clear],
                               center: UnitPoint(x: 0.06, y: 0.98), startRadius: 0, endRadius: max(w, 300) * 0.95)

                // crescent moon and stars
                Image(systemName: "moon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(hex: 0xf3e6c4).opacity(0.2))
                    .shadow(color: Color(hex: 0xf3e6c4).opacity(0.25), radius: 18)
                    .rotationEffect(.degrees(-24))
                    .position(x: w - 58, y: 96)
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, s in
                    Image(systemName: "sparkle")
                        .font(.system(size: s.s))
                        .foregroundStyle(Color(hex: 0xfff1c9).opacity(0.28))
                        .position(x: w * s.x, y: h * s.y)
                }

                // herbs drying on a string, top left
                HerbBundle()
                    .stroke(Color(hex: 0x8a9a52).opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 70, height: 130)
                    .position(x: 46, y: 70)

                // laurel along the bottom corners, and a little mushroom
                Image(systemName: "laurel.leading")
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(Color(hex: 0x7f9446).opacity(0.13))
                    .position(x: 34, y: h - 120)
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 110, weight: .light))
                    .foregroundStyle(Color(hex: 0x7f9446).opacity(0.13))
                    .position(x: w - 34, y: h - 120)
                Mushroom()
                    .fill(Color(hex: 0xc0563f).opacity(0.16))
                    .frame(width: 34, height: 30)
                    .position(x: w - 86, y: h - 66)

                // fireflies
                ForEach(Array(Self.flies.enumerated()), id: \.offset) { _, f in
                    Circle()
                        .fill(Color(hex: 0xffd77d))
                        .frame(width: 4, height: 4)
                        .shadow(color: Color(hex: 0xffc35a), radius: 5)
                        .opacity(drift ? 0.75 : 0.25)
                        .position(x: w * f.x, y: h * f.y)
                        .offset(x: drift ? f.dx : 0, y: drift ? f.dy : 0)
                        .animation(.easeInOut(duration: f.t).repeatForever(autoreverses: true), value: drift)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { drift = true }
    }
}

/// a few sprigs tied to a string (drawn as lines)
private struct HerbBundle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = CGPoint(x: r.minX + r.width * 0.3, y: r.minY)
        let knot = CGPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.32)
        p.move(to: top); p.addLine(to: knot)                                   // the string
        for (i, a) in [-0.5, -0.2, 0.1, 0.4].enumerated() {                   // the stems
            let len = r.height * (0.62 - CGFloat(i % 2) * 0.08)
            let end = CGPoint(x: knot.x + sin(a) * len, y: knot.y + cos(a) * len)
            p.move(to: knot); p.addLine(to: end)
            // little leaves along each stem
            for k in 1...4 {
                let t = CGFloat(k) / 5
                let base = CGPoint(x: knot.x + (end.x - knot.x) * t, y: knot.y + (end.y - knot.y) * t)
                let side: CGFloat = k.isMultiple(of: 2) ? 1 : -1
                p.move(to: base)
                p.addQuadCurve(to: CGPoint(x: base.x + side * 9, y: base.y + 6), control: CGPoint(x: base.x + side * 8, y: base.y - 2))
            }
        }
        return p
    }
}

/// a small toadstool
private struct Mushroom: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let capBottom = r.minY + r.height * 0.5
        p.move(to: CGPoint(x: r.minX, y: capBottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: capBottom), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.45))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: r.midX - r.width * 0.13, y: capBottom - 1, width: r.width * 0.26, height: r.height * 0.5),
                         cornerSize: CGSize(width: 4, height: 4))
        return p
    }
}

// MARK: - 星空

/// 星空: deep space. A dark blue-black sky with soft violet and teal nebulas, a field of stars (some of them
/// twinkling), a ringed planet in a corner and a small moon. Faint, and it lets every touch through.
struct SpaceBackground: View {
    @State private var twinkle = false

    /// the same stars every time: places and sizes from a fixed sequence
    private static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, tw: Bool)] = {
        var out: [(x: CGFloat, y: CGFloat, r: CGFloat, tw: Bool)] = []
        var x: UInt64 = 0x2545F4914F6CDD1D
        func next() -> CGFloat { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return CGFloat(x % 10_000) / 10_000 }
        for i in 0..<90 { out.append((x: next(), y: next(), r: 0.5 + next() * 1.4, tw: i % 6 == 0)) }
        return out
    }()

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0d1024), Color(hex: 0x0a0c18), Color(hex: 0x07080f)],
                               startPoint: .top, endPoint: .bottom)
                // nebulas
                RadialGradient(colors: [Color(hex: 0x7a4cff).opacity(0.20), .clear],
                               center: UnitPoint(x: 0.85, y: 0.22), startRadius: 0, endRadius: max(w, 300) * 0.7)
                RadialGradient(colors: [Color(hex: 0x2fd3c0).opacity(0.12), .clear],
                               center: UnitPoint(x: 0.1, y: 0.7), startRadius: 0, endRadius: max(w, 300) * 0.8)
                RadialGradient(colors: [Color(hex: 0xff5ca8).opacity(0.08), .clear],
                               center: UnitPoint(x: 0.55, y: 0.95), startRadius: 0, endRadius: max(w, 300) * 0.6)
                // stars
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, s in
                    Circle()
                        .fill(Color.white)
                        .frame(width: s.r * 2, height: s.r * 2)
                        .opacity(s.tw ? (twinkle ? 0.9 : 0.2) : 0.45)
                        .shadow(color: .white.opacity(s.tw ? 0.8 : 0), radius: 3)
                        .position(x: w * s.x, y: h * s.y)
                        .animation(s.tw ? .easeInOut(duration: 2.5 + Double(s.r)).repeatForever(autoreverses: true) : nil, value: twinkle)
                }
                // a ringed planet, bottom right, and a small moon
                Planet()
                    .frame(width: 150, height: 150)
                    .opacity(0.32)
                    .position(x: w - 50, y: h - 150)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xc9d2ff), Color(hex: 0x6a74b8)], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
                    .opacity(0.35)
                    .position(x: 60, y: 120)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { twinkle = true }
    }
}

/// a planet with a tilted ring
private struct Planet: View {
    var body: some View {
        ZStack {
            Ellipse()
                .stroke(Color(hex: 0xffd9a0).opacity(0.7), lineWidth: 5)
                .frame(width: 150, height: 40)
                .rotationEffect(.degrees(-18))
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xffc28a), Color(hex: 0xb4507a), Color(hex: 0x3b2266)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60))
                .frame(width: 84, height: 84)
            // the front half of the ring, over the planet
            Ellipse()
                .trim(from: 0.0, to: 0.5)
                .stroke(Color(hex: 0xffd9a0).opacity(0.8), lineWidth: 5)
                .frame(width: 150, height: 40)
                .rotationEffect(.degrees(-18))
        }
    }
}

// MARK: - 苔蘚小窩 (goblincore)

/// 苔蘚小窩: the forest floor. Damp earth, patches of moss, ferns along the sides, a cluster of toadstools,
/// pebbles, a ladybug, a snail shell, and little found treasures (a key, a button, a coin), with dewdrops
/// catching the light. Faint, and it lets every touch through.
struct GoblinBackground: View {
    @State private var glint = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1c2016), Color(hex: 0x19190f), Color(hex: 0x15120c)],
                               startPoint: .top, endPoint: .bottom)
                // moss patches
                RadialGradient(colors: [Color(hex: 0x6f8f2a).opacity(0.20), .clear],
                               center: UnitPoint(x: 0.15, y: 1.0), startRadius: 0, endRadius: max(w, 300) * 0.7)
                RadialGradient(colors: [Color(hex: 0x5c7d2b).opacity(0.14), .clear],
                               center: UnitPoint(x: 0.95, y: 0.85), startRadius: 0, endRadius: max(w, 300) * 0.55)
                RadialGradient(colors: [Color(hex: 0x8aa53a).opacity(0.08), .clear],
                               center: UnitPoint(x: 0.7, y: 0.0), startRadius: 0, endRadius: max(w, 300) * 0.6)

                // ferns along the sides
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 46 - CGFloat(i) * 8))
                        .foregroundStyle(Color(hex: 0x7a9a36).opacity(0.14))
                        .rotationEffect(.degrees(40 + Double(i) * 18))
                        .position(x: 18 + CGFloat(i) * 10, y: h * 0.32 + CGFloat(i) * 46)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 40 - CGFloat(i) * 7))
                        .foregroundStyle(Color(hex: 0x7a9a36).opacity(0.12))
                        .rotationEffect(.degrees(-130 - Double(i) * 16))
                        .position(x: w - 18 - CGFloat(i) * 10, y: h * 0.18 + CGFloat(i) * 44)
                }

                // toadstools, pebbles and treasures along the bottom
                ForEach(Array([(0.10, 34.0, 0xb5543c), (0.17, 22.0, 0x9a7b4f), (0.22, 16.0, 0xc0563f)].enumerated()), id: \.offset) { _, m in
                    ToadstoolShape()
                        .fill(Color(hex: UInt32(m.2)).opacity(0.22))
                        .frame(width: m.1, height: m.1 * 0.9)
                        .position(x: w * m.0, y: h - 52 - m.1 * 0.3)
                }
                ForEach(Array([(0.42, 18.0, 10.0), (0.47, 11.0, 7.0), (0.80, 15.0, 9.0), (0.62, 9.0, 6.0)].enumerated()), id: \.offset) { _, p in
                    Ellipse()
                        .fill(Color(hex: 0x8d8a7a).opacity(0.16))
                        .frame(width: p.1, height: p.2)
                        .position(x: w * p.0, y: h - 40)
                }
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0xd0503c).opacity(0.3))
                    .rotationEffect(.degrees(-25))
                    .position(x: w * 0.88, y: h - 96)
                SnailShell()
                    .stroke(Color(hex: 0xc9a46a).opacity(0.25), lineWidth: 2.2)
                    .frame(width: 24, height: 24)
                    .position(x: w * 0.70, y: h - 64)
                Image(systemName: "key.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0xd8b25a).opacity(0.26))
                    .rotationEffect(.degrees(30))
                    .position(x: w * 0.33, y: h - 70)
                Image(systemName: "circle.grid.2x2.fill")            // a button
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xc78a6a).opacity(0.3))
                    .position(x: w * 0.55, y: h - 58)

                // dewdrops / shiny things catching the light
                ForEach(Array([(0.25, 0.86), (0.58, 0.78), (0.84, 0.9), (0.12, 0.55), (0.9, 0.42)].enumerated()), id: \.offset) { i, d in
                    Image(systemName: "sparkle")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(hex: 0xe8f2c8))
                        .opacity(glint ? 0.55 : 0.08)
                        .position(x: w * d.0, y: h * d.1)
                        .animation(.easeInOut(duration: 2.2 + Double(i) * 0.7).repeatForever(autoreverses: true), value: glint)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { glint = true }
    }
}

/// a toadstool with a round cap and a stem
private struct ToadstoolShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let capBottom = r.minY + r.height * 0.52
        p.move(to: CGPoint(x: r.minX, y: capBottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: capBottom), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: r.midX - r.width * 0.14, y: capBottom - 1, width: r.width * 0.28, height: r.height * 0.48),
                         cornerSize: CGSize(width: 4, height: 4))
        return p
    }
}

/// a spiral snail shell
private struct SnailShell: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let maxR = min(r.width, r.height) / 2
        var first = true
        for i in 0...90 {
            let t = Double(i) / 90
            let a = t * 2.6 * 2 * .pi
            let rr = maxR * CGFloat(t)
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
        }
        return p
    }
}
