import AppIntents
import SwiftUI

/// which tab is showing; Shortcuts can switch it
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab = 0

    /// open 詞典 → 查詞 with this word
    func lookUp(_ word: String) {
        UserDefaults.standard.set(0, forKey: "dictTab")
        UserDefaults.standard.set(word, forKey: "lookupQuery")
        tab = 4
    }
}

// MARK: - Shortcuts

/// Opens the app's dictionary with the word: there you can play the recordings, save to 收藏 (exportable)
/// or add to 不熟.
struct LookUpIntent: AppIntent {
    static var title: LocalizedStringResource = "在方方詞卡查詞"
    static var description = IntentDescription("打開方方詞卡的「詞典」，查這個詞（華語、台語漢字、羅馬字或方音都可以）。在那裡可以聽發音、收藏、加到「不熟」。")
    static var openAppWhenRun = true

    @Parameter(title: "詞")
    var word: String

    static var parameterSummary: some ParameterSummary {
        Summary("在方方詞卡查 \(\.$word)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.lookUp(word.trimmingCharacters(in: .whitespacesAndNewlines))
        return .result()
    }
}

/// Looks the word up without opening the app and gives back the readings and meanings as text.
struct QuickLookUpIntent: AppIntent {
    static var title: LocalizedStringResource = "方方快速查詞"
    static var description = IntentDescription("不打開 App，查這個詞，回傳漢字、讀音和意思（文字）。要聽發音或收藏，請用「在方方詞卡查詞」。")
    static var openAppWhenRun = false

    @Parameter(title: "詞")
    var word: String

    static var parameterSummary: some ParameterSummary {
        Summary("快速查 \(\.$word)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let q = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Bundle.main.url(forResource: "dict", withExtension: "json") else {
            return .result(value: "", dialog: "找不到詞典資料。")
        }
        let data = try Data(contentsOf: url)
        let d = Dict(try JSONDecoder().decode(DictRaw.self, from: data))
        let rom = UserDefaults.standard.object(forKey: "rom") as? Int ?? 0
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        let r = Lookup.run(d, q)
        var keys: [String] = []
        for k in r.taigi + r.exact + r.pattern + r.contains + r.patternZh + r.gloss + r.defs where !keys.contains(k) { keys.append(k) }
        if keys.isEmpty { return .result(value: "", dialog: IntentDialog(stringLiteral: "找不到「\(q)」。")) }
        let lines = keys.prefix(8).map { k -> String in
            var line = Dict.hanOf(k) + "　" + d.word(k, rom, place) + "　" + d.word(k, 3, place)
            if let g = d.gl[k], !g.isEmpty { line += "\n　" + g.prefix(5).map { $0.t }.joined(separator: "、") }
            else if let t = d.defText(k) { line += "\n　" + t.replacingOccurrences(of: "\n", with: " ") }
            return line
        }
        let text = lines.joined(separator: "\n")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct FangfangShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LookUpIntent(),
                    phrases: ["在\(.applicationName)查詞", "用\(.applicationName)查詞", "Look up a word in \(.applicationName)"],
                    shortTitle: "查詞",
                    systemImageName: "character.book.closed")
        AppShortcut(intent: QuickLookUpIntent(),
                    phrases: ["用\(.applicationName)快速查詞"],
                    shortTitle: "快速查詞",
                    systemImageName: "text.magnifyingglass")
    }
}
