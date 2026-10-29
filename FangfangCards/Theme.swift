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
    /// guessed (推測) readings
    static let guessInk = Color(hex: 0xff7a6e)
    /// a word swapped for the one the chosen place uses (各地講法)
    static let swapInk = Color(hex: 0xff9fd2)
    static let pinkEdge = Color(hex: 0xa04a78)
    static let pinkInk = Color(hex: 0xf8cbe2)
    /// your own words (自訂), not from the MOE dictionary
    static let ownInk = Color(hex: 0xc39bff)
    static let own = Color(hex: 0x4c3a5b)
    static let ownEdge = Color(hex: 0x7b3c9b)

    /// 皓羅 / 台羅 / 白話字 text
    static func lat(_ size: CGFloat) -> Font { .custom("DejaVuSans", size: size) }
}

let ROM_NAMES = ["皓羅", "台羅", "白話字"]

/// the 10 places of the MOE dictionary's 語音差異, in the data's order (腔口 index = position)
let PLACE_NAMES = ["鹿港偏泉腔", "三峽偏泉腔", "臺北偏泉腔", "宜蘭偏漳腔", "臺南混合腔",
                   "高雄混合腔", "金門偏泉腔", "馬公偏泉腔", "新竹偏泉腔", "臺中偏漳腔"]

/// The spelling button (taps through 皓羅 → 台羅 → 白話字) with the 腔口 picker next to it.
/// It's in the top bar of every page except 設定.
struct RomButton: View {
    @AppStorage("rom") private var rom = 0
    @AppStorage("glass") private var glassOn = true
    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy) { rom = (rom + 1) % 3 }
            } label: {
                label
            }
            .accessibilityLabel("切換羅馬字")
            #if targetEnvironment(macCatalyst)
            .buttonStyle(.plain)          // Mac: the same one-tap capsule as on the phone, not a toolbar button
            .fixedSize()
            #endif
            PlaceMenu()
            ToneMenu()
        }
        #if targetEnvironment(macCatalyst)
        .fixedSize()
        #endif
    }

    @ViewBuilder private var label: some View {
        #if targetEnvironment(macCatalyst)
        capsule
        #else
        if glassOn {
            if #available(iOS 26.0, *) {
                plainText   // the iOS 26 toolbar already puts this in glass
            } else {
                capsule
            }
        } else {
            capsule
        }
        #endif
    }
    private var plainText: some View {
        Text(ROM_NAMES[min(max(rom, 0), 2)])
            .ffFont(.subheadline, .bold)
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
            .ffFont(.caption, .bold)
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
            .ffFont(.caption2, .heavy)
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

/// 腔口: 通行 or one of the 10 places
struct PlaceMenu: View {
    @AppStorage("place") private var place = -1
    @AppStorage("glass") private var glassOn = true
    var body: some View {
        Menu {
            Picker("腔口", selection: $place) {
                Text("通行").tag(-1)
                ForEach(Array(PLACE_NAMES.enumerated()), id: \.offset) { i, p in Text(p).tag(i) }
            }
            .pickerStyle(.inline)         // the places right in the menu (on the Mac it was a submenu)
        } label: {
            label
        }
        .accessibilityLabel("腔口")
        #if targetEnvironment(macCatalyst)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    private var name: String { place >= 0 && place < PLACE_NAMES.count ? String(PLACE_NAMES[place].prefix(2)) : "通行" }

    @ViewBuilder private var label: some View {
        #if targetEnvironment(macCatalyst)
        capsule
        #else
        if glassOn {
            if #available(iOS 26.0, *) {
                plainText      // the iOS 26 toolbar already puts this in glass
            } else {
                capsule
            }
        } else {
            capsule
        }
        #endif
    }
    private var capsule: some View {
        plainText
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color(hex: 0x4c3a5b)))
            .overlay(Capsule().stroke(Color(hex: 0x7b3c9b), lineWidth: 2))
    }
    private var plainText: some View {
        HStack(spacing: 2) {
            Text(name).ffFont(.subheadline, .bold)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(T.purpleInk)
    }
}

// MARK: text size (Mac)

/// Mac: how big the text is (設定 → 文字大小, or ⌘+ / ⌘− / ⌘0). iPhone and iPad follow the system's text size.
enum TextSize {
    static let levels: [DynamicTypeSize] = [.large, .xLarge, .xxLarge, .xxxLarge,
                                            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
    static let names = ["100%", "110%", "120%", "135%", "160%", "190%", "235%", "275%", "310%"]
    static let key = "macTextSize2"
    static let standard = 3                   // 135%: the Mac's own text sizes are small on a big screen
    static func clamp(_ i: Int) -> Int { min(max(i, 0), levels.count - 1) }
}

struct MacTextSize: ViewModifier {
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // text without a style of its own (form rows, list rows…) at the chosen size too
        content.font(.system(size: 17 * 0.77 * TextSize.factor(level)))
            // and what the system draws itself (sidebar, menus, text fields), as far as it follows it
            .onAppear { MacWindow.applyTextSize(level) }
            .onChange(of: level) { MacWindow.applyTextSize(level) }
        #else
        content
        #endif
    }
}

extension TextSize {
    /// Mac: how much bigger than the Mac's own text sizes (100% = the system's size)
    static let factors: [CGFloat] = [1.0, 1.1, 1.2, 1.35, 1.6, 1.9, 2.35, 2.75, 3.1]
    static func factor(_ level: Int) -> CGFloat { factors[min(max(level, 0), factors.count - 1)] }
}

/// The app's text styles. On the Mac they're sized by 設定 → 文字大小 (the system ignores text size there);
/// on iPhone/iPad they're the usual text styles, which follow the phone's own text size.
enum FFStyle {
    case body, callout, subheadline, footnote, caption, caption2, headline, title3, title2, title, largeTitle
    var font: Font {
        switch self {
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        case .largeTitle: return .largeTitle
        }
    }
    /// sizes on iPad (what the app was designed with)
    var size: CGFloat {
        switch self {
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        case .headline: return 17
        case .title3: return 20
        case .title2: return 22
        case .title: return 28
        case .largeTitle: return 34
        }
    }
}

struct FFFont: ViewModifier {
    let style: FFStyle
    var weight: Font.Weight? = nil
    var mono = false
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // Mac sizes are the iPad sizes × 0.77 (how Mac text compares to iPad text), then the chosen factor
        let f = Font.system(size: style.size * 0.77 * TextSize.factor(level),
                            weight: weight ?? (style == .headline ? .semibold : .regular))
        content.font(mono ? f.monospacedDigit() : f)
        #else
        let f = weight.map { style.font.weight($0) } ?? style.font
        content.font(mono ? f.monospacedDigit() : f)
        #endif
    }
}

/// 皓羅 / 台羅 / 白話字 text (DejaVu Sans), sized with the Mac text size
struct LatFont: ViewModifier {
    let size: CGFloat
    @AppStorage(TextSize.key) private var level = TextSize.standard
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.font(.custom("DejaVuSans", fixedSize: size * 0.77 * TextSize.factor(level)))
        #else
        content.font(T.lat(size))
        #endif
    }
}

/// a fixed-size system font that grows with the Mac text size (on iPhone/iPad it stays as it was)
struct ScaledFont: ViewModifier {
    private let size: CGFloat
    private let weight: Font.Weight
    private let on: Bool
    @AppStorage(TextSize.key) private var level = TextSize.standard
    init(_ size: CGFloat, weight: Font.Weight, on: Bool) {
        self.size = size; self.weight = weight; self.on = on
    }
    @ViewBuilder func body(content: Content) -> some View {
        if !on {
            content
        } else {
            #if targetEnvironment(macCatalyst)
            content.font(.system(size: size * 0.77 * TextSize.factor(level), weight: weight))
            #else
            content.font(.system(size: size, weight: weight))
            #endif
        }
    }
}

extension View {
    func macTextSize() -> some View { modifier(MacTextSize()) }
    func ffFont(_ style: FFStyle, _ weight: Font.Weight? = nil, mono: Bool = false) -> some View {
        modifier(FFFont(style: style, weight: weight, mono: mono))
    }
    func latFont(_ size: CGFloat) -> some View { modifier(LatFont(size: size)) }
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, on: Bool = true) -> some View {
        modifier(ScaledFont(size, weight: weight, on: on))
    }
}

/// Mac menu bar: 顯示 → 放大 / 縮小 / 實際大小
struct TextSizeCommands: Commands {
    @AppStorage(TextSize.key) private var level = TextSize.standard
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("放大文字") { level = TextSize.clamp(level + 1) }
                .keyboardShortcut("=", modifiers: .command)   // ⌘+ (the + key is ⇧=)
                .disabled(level >= TextSize.levels.count - 1)
            Button("縮小文字") { level = TextSize.clamp(level - 1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(level <= 0)
            Button("實際大小") { level = TextSize.standard }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
