import SwiftUI

// Liquid Glass (iOS 26) with a plain 方方-style fallback for older iOS or when switched off in 設定.

@available(iOS 26.0, *)
private func makeGlass(_ tint: Color?, _ interactive: Bool) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var interactive = false
    var fallback: Color = T.fn
    var edge: Color = T.fnEdge
    @AppStorage("glass2") private var glassOn = false

    func body(content: Content) -> some View {
        if glassOn {
            if #available(iOS 26.0, *) {
                content.glassEffect(makeGlass(tint, interactive), in: shape)
            } else {
                plain(content)
            }
        } else {
            plain(content)
        }
    }

    private func plain(_ content: Content) -> some View {
        content
            .background(shape.fill(fallback))
            .overlay(shape.stroke(edge, lineWidth: 2))
    }
}

/// The swipe cards: frosted glass with a bright rim. (Real Liquid Glass stretches like liquid
/// when a big surface is dragged around, so the cards use this instead.)
struct CardSurface: ViewModifier {
    var frosted = true                    // only the top card needs the (costly) blur
    @AppStorage("glass2") private var glassOn = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if glassOn {
            content
                .background(shape.fill(T.fn.opacity(frosted ? 0.35 : 0.92)))
                .background {
                    // shadow drawn from the shape only, not from the whole card content
                    if frosted {
                        shape.fill(.ultraThinMaterial).shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                    } else {
                        shape.fill(T.fn).shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                    }
                }
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.06), Color.white.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)
                )
        } else {
            content
                .background(shape.fill(T.fn))
                .overlay(shape.stroke(T.keyEdge, lineWidth: 2))
        }
    }
}

struct ProminentButton: ViewModifier {
    var tint: Color = T.greenEdge
    @AppStorage("glass2") private var glassOn = false

    func body(content: Content) -> some View {
        if glassOn {
            if #available(iOS 26.0, *) {
                content.buttonStyle(.glassProminent).tint(tint)
            } else {
                content.buttonStyle(.borderedProminent).tint(tint)
            }
        } else {
            content.buttonStyle(.borderedProminent).tint(tint)
        }
    }
}

/// Mac: a quiet frosted button. The system styles fill with the accent colour while the window is active,
/// which made them bright green there.
struct MacSoftStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? T.glyph : T.muted)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(configuration.isPressed ? T.key : T.fn.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.fnEdge, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SoftButton: ViewModifier {
    @AppStorage("glass2") private var glassOn = false

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.buttonStyle(MacSoftStyle())
        #else
        softBody(content)
        #endif
    }

    @ViewBuilder private func softBody(_ content: Content) -> some View {
        if glassOn {
            if #available(iOS 26.0, *) {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.bordered)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false,
                                fallback: Color = T.fn, edge: Color = T.fnEdge) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive, fallback: fallback, edge: edge))
    }
    func prominentButton(_ tint: Color = T.greenEdge) -> some View { modifier(ProminentButton(tint: tint)) }
    func softButton() -> some View { modifier(SoftButton()) }
    /// the moving colour background that the glass refracts
    func appBackground() -> some View { background { AppBackground() } }
}

/// Soft, slowly drifting colour light behind everything, in the 方方 key colours.
struct AppBackground: View {
    @State private var move = false
    @AppStorage("glass2") private var glassOn = false

    var body: some View {
        switch AppTheme.current {
        case .witch: WitchBackground()
        case .space: SpaceBackground()
        case .goblin: GoblinBackground()
        case .night: nightBody
        }
    }

    private var nightBody: some View {
        ZStack {
            T.bg
            if glassOn {
                ZStack {
                blob(T.blueEdge, 0.55, 440, a: CGSize(width: -130, height: -280), b: CGSize(width: 150, height: -150))
                blob(T.greenEdge, 0.50, 400, a: CGSize(width: 160, height: 240), b: CGSize(width: -120, height: 340))
                blob(Color(hex: 0x7b3c9b), 0.42, 320, a: CGSize(width: 70, height: 30), b: CGSize(width: -60, height: -40))
                blob(T.oliveEdge, 0.30, 260, a: CGSize(width: -150, height: 120), b: CGSize(width: 140, height: 60))
                }
                // animation scoped to the blobs only
                .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: move)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { move = true }
    }

    // a soft radial gradient looks like a blurred circle but costs almost nothing to draw
    private func blob(_ c: Color, _ o: Double, _ size: CGFloat, a: CGSize, b: CGSize) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(o), c.opacity(o * 0.5), c.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size * 0.75))
            .frame(width: size * 1.5, height: size * 1.5)
            .offset(move ? b : a)
    }
}
