import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

/// Same colours as the 方方 website and Safari extension.
enum T {
    static let bg = Color(hex: 0x1c1c1e)
    static let key = Color(hex: 0x4a4a4c)
    static let keyEdge = Color(hex: 0x6d6d70)
    static let fn = Color(hex: 0x2b2b2d)
    static let fnEdge = Color(hex: 0x4b4b4e)
    static let glyph = Color(hex: 0xf2f2f2)
    static let muted = Color(hex: 0xa3a3a8)
    static let blue = Color(hex: 0x34405e)
    static let blueEdge = Color(hex: 0x3d4f9c)
    static let blueInk = Color(hex: 0xc8cfff)
    static let green = Color(hex: 0x44503a)
    static let greenEdge = Color(hex: 0x4f6c32)
    static let greenInk = Color(hex: 0xd4efc0)
    static let purpleInk = Color(hex: 0xe3c6f7)
    static let olive = Color(hex: 0x5a5238)
    static let oliveEdge = Color(hex: 0x8c7a38)
    static let oliveInk = Color(hex: 0xf1e3ae)
    static let rust = Color(hex: 0x5b4136)
    static let rustEdge = Color(hex: 0x8b4a2d)
    static let rustInk = Color(hex: 0xf3c9b2)
    static let pink = Color(hex: 0x5e3a4f)
    static let pinkEdge = Color(hex: 0xa04a78)
    static let pinkInk = Color(hex: 0xf8cbe2)

    /// 皓羅 / 台羅 / 白話字 text
    static func lat(_ size: CGFloat) -> Font { .custom("DejaVuSans", size: size) }
}

let ROM_NAMES = ["皓羅", "台羅", "白話字"]

/// Taps through 皓羅 → 台羅 → 白話字.
struct RomButton: View {
    @AppStorage("rom") private var rom = 0
    @AppStorage("glass") private var glassOn = true
    var body: some View {
        Button {
            withAnimation(.snappy) { rom = (rom + 1) % 3 }
        } label: {
            label
        }
        .accessibilityLabel("切換羅馬字")
    }

    @ViewBuilder private var label: some View {
        if glassOn {
            if #available(iOS 26.0, *) {
                plainText   // the iOS 26 toolbar already puts this in glass
            } else {
                capsule
            }
        } else {
            capsule
        }
    }
    private var plainText: some View {
        Text(ROM_NAMES[min(max(rom, 0), 2)])
            .font(.subheadline.weight(.bold))
            .foregroundStyle(T.greenInk)
    }
    private var capsule: some View {
        plainText
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(T.green))
            .overlay(Capsule().stroke(T.greenEdge, lineWidth: 2))
    }
}

struct Chip: View {
    let text: String
    var fill: Color = T.olive
    var edge: Color = T.oliveEdge
    var ink: Color = T.oliveInk
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(edge, lineWidth: 1.5))
            .foregroundStyle(ink)
    }
}

/// 白 / 文 / 俗 label
struct RegChip: View {
    let reg: String
    var body: some View {
        switch reg {
        case "白": Chip(text: "白", fill: T.green, edge: T.greenEdge, ink: T.greenInk)
        case "文": Chip(text: "文", fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
        case "俗": Chip(text: "俗", fill: T.rust, edge: T.rustEdge, ink: T.rustInk)
        default: EmptyView()
        }
    }
}

struct NumBadge: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.caption2.weight(.heavy))
            .frame(minWidth: 18, minHeight: 18)
            .background(Circle().fill(T.fn))
            .overlay(Circle().stroke(T.oliveEdge, lineWidth: 1.5))
            .foregroundStyle(T.oliveInk)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 22), tint: T.fn.opacity(0.45))
    }
}
