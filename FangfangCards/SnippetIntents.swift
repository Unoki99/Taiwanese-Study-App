import AppIntents
import SwiftUI
import AVFoundation

// 方方查詞（小視窗）: a Shortcuts action that shows the dictionary entries for a word in a small card on top
// of whatever app you're in (iOS / iPadOS / macOS 26). The card has buttons to play the recording,
// save to 收藏, add to 不熟, or open the entry in the app.

/// the dictionary, loaded once per launch for Shortcuts actions
@MainActor
final class IntentDict {
    static let shared = IntentDict()
    private var dict: Dict?
    func get() throws -> Dict {
        if let d = dict { return d }
        if let d = Store.shared.dict { dict = d; return d }
        guard let url = Bundle.main.url(forResource: "dict", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let d = Dict(try JSONDecoder().decode(DictRaw.self, from: Data(contentsOf: url)))
        dict = d
        return d
    }
}

/// one entry on the card
struct SnippetRow: Identifiable {
    let key: String
    let han: String
    let rom: AttributedString
    let zy: AttributedString
    let gloss: String
    let audio: String?
    let saved: Bool
    let status: Int?            // nil = not a card, 0 new, 1 熟悉, 2 不熟
    var id: String { key }
}

@available(iOS 26.0, *)
struct PopupLookUpIntent: AppIntent {
    static let title: LocalizedStringResource = "方方查詞（小視窗）"
    static let description = IntentDescription("在畫面上用小視窗顯示這個詞的辭典結果（華語、台語漢字、羅馬字或方音都可以）。可以聽發音、收藏、加到「不熟」，不用打開 App。")

    @Parameter(title: "詞")
    var word: String

    static var parameterSummary: some ParameterSummary {
        Summary("用小視窗查 \(\.$word)")
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: LookUpSnippetIntent(word: word.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}

@available(iOS 26.0, *)
struct LookUpSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "方方查詞結果"
    static let isDiscoverable = false

    @Parameter(title: "詞")
    var word: String

    init() {}
    init(word: String) { self.word = word }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let d = try IntentDict.shared.get()
        let store = Store.shared
        store.load()
        let rom = UserDefaults.standard.object(forKey: "rom") as? Int ?? 0
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        let r = Lookup.run(d, word)
        var keys: [String] = []
        for k in r.taigi + r.exact + r.pattern + r.contains + r.patternZh + r.gloss + r.defs where !keys.contains(k) { keys.append(k) }
        let rows = keys.prefix(4).map { k -> SnippetRow in
            var gloss = ""
            if let g = d.gl[k], !g.isEmpty { gloss = g.prefix(5).map { $0.t }.joined(separator: "、") }
            else if let t = d.defText(k) {
                gloss = t.replacingOccurrences(of: #"\d+\.\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\n", with: "／")
            }
            return SnippetRow(key: k, han: Dict.hanOf(k), rom: d.wordText(k, min(max(rom, 0), 2), place),
                              zy: d.wordText(k, 3, place), gloss: gloss,
                              audio: d.raw.au[k].map { Audio.wordPath($0) },
                              saved: store.isSaved(k), status: store.cardStatus(k))
        }
        return .result(view: LookUpSnippetView(word: word, rows: Array(rows), more: keys.count > rows.count))
    }
}

@available(iOS 26.0, *)
struct LookUpSnippetView: View {
    let word: String
    let rows: [SnippetRow]
    let more: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text("找不到「\(word)」。").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(row.han).ffFont(.title3, .semibold)
                        Text(row.rom).latFont(16).foregroundStyle(.green)
                            .pill(.green)
                        Text(row.zy).ffFont(.footnote).foregroundStyle(.purple)
                            .pill(.purple)
                        Spacer(minLength: 0)
                    }
                    if !row.gloss.isEmpty {
                        Text(row.gloss).ffFont(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    buttons(row)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.45), lineWidth: 1.5))
            }
            if more {
                Button(intent: OpenLookUpIntent(word: word)) {
                    Label("在 App 裡看全部", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    @ViewBuilder private func buttons(_ row: SnippetRow) -> some View {
        HStack(spacing: 8) {
            if let a = row.audio {
                Button(intent: PlayRecordingIntent(path: a)) { Image(systemName: "play.fill") }
                    .buttonStyle(.bordered).tint(.green)
            }
            Button(intent: ToggleSavedIntent(key: row.key)) {
                Label(row.saved ? "已收藏" : "收藏", systemImage: row.saved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.bordered).tint(.yellow)
            if let st = row.status {
                if st == 1 {
                    Text("熟悉").ffFont(.caption).foregroundStyle(.green)
                } else {
                    Button(intent: ToggleUnknownIntent(key: row.key)) {
                        Label(st == 2 ? "在不熟" : "加到不熟", systemImage: st == 2 ? "star.fill" : "star")
                    }
                    .buttonStyle(.bordered).tint(.orange)
                }
            }
            Spacer(minLength: 0)
            Button(intent: OpenLookUpIntent(word: row.han)) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered)
        }
        .ffFont(.caption)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - the card's buttons

@available(iOS 26.0, *)
struct PlayRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "播放發音"
    static let isDiscoverable = false
    @Parameter var path: String
    init() {}
    init(path: String) { self.path = path }

    @MainActor
    func perform() async throws -> some IntentResult {
        // play over whatever app is on screen (needs the "audio" background mode, see FangfangCards-Info.plist)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        Player.shared.play(path)
        // wait for the download to start playing, then for it to finish
        try? await Task.sleep(nanoseconds: 300_000_000)
        // stay until the recording has played, so it isn't cut off
        for _ in 0..<50 {
            if Player.shared.playing != path { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        return .result()
    }
}

@available(iOS 26.0, *)
struct ToggleSavedIntent: AppIntent {
    static let title: LocalizedStringResource = "收藏／取消收藏"
    static let isDiscoverable = false
    @Parameter var key: String
    init() {}
    init(key: String) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        let s = Store.shared
        s.load()
        s.toggleSaved(key)
        s.saveNow()
        return .result()
    }
}

@available(iOS 26.0, *)
struct ToggleUnknownIntent: AppIntent {
    static let title: LocalizedStringResource = "加到不熟"
    static let isDiscoverable = false
    @Parameter var key: String
    init() {}
    init(key: String) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        let s = Store.shared
        s.load()
        s.toggleUnknown(key)
        s.saveNow()
        return .result()
    }
}

@available(iOS 26.0, *)
struct OpenLookUpIntent: AppIntent {
    static let title: LocalizedStringResource = "在方方詞卡打開"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter var word: String
    init() {}
    init(word: String) { self.word = word }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.lookUp(word)
        return .result()
    }
}

extension View {
    /// a reading in a rounded box of its own colour, matching the card's buttons
    func pill(_ c: Color) -> some View {
        padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.14)))
            .overlay(Capsule().stroke(c.opacity(0.55), lineWidth: 1))
    }
}
