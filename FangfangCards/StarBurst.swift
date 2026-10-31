import SwiftUI

/// 練習: tap anywhere and a handful of little stars in the tone colours burst out from your finger,
/// then fall to the bottom of the screen. Just for fun (it doesn't block any button).
final class StarField: ObservableObject {
    struct Star: Identifiable {
        let id = UUID()
        let start: CGPoint
        let vx: CGFloat           // points per second, sideways
        let vy: CGFloat           // points per second, up is negative
        let spin: Double          // turns per second
        let size: CGFloat
        let color: Color
        let born: Date
    }
    @Published var stars: [Star] = []

    static let colors: [Color] = [ToneColors.red, ToneColors.purple, ToneColors.blue, ToneColors.orange,
                                  ToneColors.green, ToneColors.teal, ToneColors.yellow, ToneColors.pink]

    func burst(at p: CGPoint) {
        let now = Date()
        let n = Int.random(in: 5...8)
        for i in 0..<n {
            let angle = -Double.pi / 2 + Double.random(in: -1.1...1.1)          // mostly upwards
            let speed = CGFloat.random(in: 180...380)
            stars.append(Star(start: p,
                              vx: CGFloat(cos(angle)) * speed,
                              vy: CGFloat(sin(angle)) * speed,
                              spin: Double.random(in: -1.2...1.2),
                              size: CGFloat.random(in: 9...16),
                              color: StarField.colors[(i + Int.random(in: 0..<8)) % 8],
                              born: now))
        }
        if stars.count > 160 { stars.removeFirst(stars.count - 160) }
    }

    /// stars that have fallen off the bottom
    func sweep(height: CGFloat, now: Date) {
        stars.removeAll { s in StarField.position(s, now.timeIntervalSince(s.born)).y > height + 40 }
    }

    static let gravity: CGFloat = 900
    static func position(_ s: Star, _ t: Double) -> CGPoint {
        let t = CGFloat(t)
        return CGPoint(x: s.start.x + s.vx * t, y: s.start.y + s.vy * t + gravity * t * t / 2)
    }
}

/// draws the falling stars (put it on top; it lets every tap through)
struct StarLayer: View {
    @ObservedObject var field: StarField

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: field.stars.isEmpty)) { tl in
                let now = tl.date
                Canvas { ctx, size in
                    for s in field.stars {
                        let t = now.timeIntervalSince(s.born)
                        let p = StarField.position(s, t)
                        guard p.y < size.height + 40 else { continue }
                        var g = ctx
                        g.translateBy(x: p.x, y: p.y)
                        g.rotate(by: .radians(t * s.spin * 2 * .pi))
                        let path = StarLayer.star(s.size)
                        // a soft glow behind each star
                        var glow = g
                        glow.addFilter(.blur(radius: s.size * 0.45))
                        glow.fill(path, with: .color(s.color.opacity(0.8)))
                        g.fill(path, with: .color(s.color))
                    }
                }
                .onChange(of: now) { field.sweep(height: geo.size.height, now: now) }
            }
        }
        .allowsHitTesting(false)
    }

    /// a five-pointed star with rounded-looking points
    static func star(_ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let rr = i.isMultiple(of: 2) ? r : r * 0.45
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

extension View {
    /// tap anywhere → tone-coloured stars (taps still reach buttons underneath)
    func starBursts(_ field: StarField) -> some View {
        self
            .overlay(StarLayer(field: field))
            .coordinateSpace(name: "stars")
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named("stars")).onEnded { field.burst(at: $0.location) }
            )
    }
}
