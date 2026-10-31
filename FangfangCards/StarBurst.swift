import SwiftUI

/// 練習: tap anywhere and a handful of little things in the tone colours burst out from your finger,
/// then fall to the bottom of the screen. Stars, plus something for each theme: little moons and herb leaves
/// (女巫小屋), planets (星空), mushrooms, leaves and acorns (苔蘚小窩). Just for fun (it doesn't block any button).
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
        var kind: Kind = .star
    }
    enum Kind { case star, moon, leaf, planet, mushroom, acorn }

    /// what flies in this theme (stars more often than the rest)
    private static var kinds: [Kind] {
        switch AppTheme.current {
        case .night: return [.star]
        case .witch: return [.star, .star, .moon, .leaf]
        case .space: return [.star, .star, .planet]
        case .goblin: return [.mushroom, .leaf, .acorn, .star]
        }
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
                              born: now,
                              kind: StarField.kinds.randomElement() ?? .star))
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
                        let path = StarLayer.shape(s.kind, s.size)
                        // a soft glow behind each one
                        var glow = g
                        glow.addFilter(.blur(radius: s.size * 0.45))
                        glow.fill(path, with: .color(s.color.opacity(0.8)))
                        g.fill(path, with: .color(s.color))
                        if s.kind == .planet {
                            // the ring, tilted
                            var ring = Path(ellipseIn: CGRect(x: -s.size * 1.15, y: -s.size * 0.32, width: s.size * 2.3, height: s.size * 0.64))
                            ring = ring.applying(CGAffineTransform(rotationAngle: -0.35))
                            g.stroke(ring, with: .color(s.color.opacity(0.9)), lineWidth: max(1.5, s.size * 0.14))
                        }
                    }
                }
                .onChange(of: now) { field.sweep(height: geo.size.height, now: now) }
            }
        }
        .allowsHitTesting(false)
    }

    static func shape(_ k: StarField.Kind, _ r: CGFloat) -> Path {
        switch k {
        case .star: return star(r)
        case .moon:
            // a crescent: a circle with another circle cut out of its side
            return Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
                .subtracting(Path(ellipseIn: CGRect(x: -r * 0.45, y: -r * 1.05, width: 1.9 * r, height: 1.9 * r)))
        case .leaf:
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -r))
            p.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: r * 0.95, y: 0))
            p.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -r * 0.95, y: 0))
            return p
        case .planet:
            let pr = r * 0.62
            return Path(ellipseIn: CGRect(x: -pr, y: -pr, width: 2 * pr, height: 2 * pr))
        case .mushroom:
            var p = Path()
            p.move(to: CGPoint(x: -r, y: 0))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: -r * 1.5))
            p.closeSubpath()
            p.addRoundedRect(in: CGRect(x: -r * 0.28, y: -1, width: r * 0.56, height: r * 0.95), cornerSize: CGSize(width: 3, height: 3))
            return p
        case .acorn:
            var p = Path(ellipseIn: CGRect(x: -r * 0.55, y: -r * 0.35, width: r * 1.1, height: r * 1.35))   // the nut
            p.addRoundedRect(in: CGRect(x: -r * 0.72, y: -r * 0.62, width: r * 1.44, height: r * 0.45),       // the cap
                             cornerSize: CGSize(width: r * 0.2, height: r * 0.2))
            p.addRect(CGRect(x: -r * 0.06, y: -r * 0.9, width: r * 0.12, height: r * 0.3))                     // the stalk
            return p
        }
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
            // the whole screen catches taps (also the empty parts), not just the buttons and text
            .contentShape(Rectangle())
            .overlay(StarLayer(field: field))
            .coordinateSpace(name: "stars")
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named("stars")).onEnded { field.burst(at: $0.location) }
            )
    }
}
