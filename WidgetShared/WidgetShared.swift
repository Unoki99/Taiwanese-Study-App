import Foundation
import AppIntents
#if !WIDGET_EXT
import AVFoundation
#endif

// Shared by the app and the widget (both targets compile this folder).
// The app writes the words of each 分類 and your progress into the App Group folder; the widget reads them.
// The widget's 收藏 button writes to an inbox that the app takes over the next time it's opened.

/// one word on the widget, with everything already written out in the app's spelling and 腔口
struct WidgetWord: Codable, Hashable {
    let k: String            // key (漢字\tcodes)
    let h: String            // 漢字
    let a: Int?              // MOE word recording
    let r: [String]          // 皓羅, 台羅, 白話字
    let z: String            // 方音
    let p: String            // word class
    let m: String            // the meaning (the one the example belongs to)
    let xh: String?          // example 漢字
    let xr: [String]?        // example 皓羅, 台羅, 白話字
    let xz: String?          // example 華語
    let xn: String?          // example recording name
    // the same texts in colour (聲調顏色, guessed readings…), piece by piece; nil in older files
    var hc: [WSeg]? = nil    // 漢字
    var rc: [[WSeg]]? = nil  // 皓羅, 台羅, 白話字
    var zc: [WSeg]? = nil    // 方音
    var xhc: [WSeg]? = nil   // example 漢字
    var xrc: [[WSeg]]? = nil // example 皓羅, 台羅, 白話字
}

/// a piece of text in one colour ("rrggbb"; nil = the widget's own colour for that line)
struct WSeg: Codable, Hashable {
    let t: String
    let c: String?
}

struct WidgetCategory: Codable, Hashable {
    let i: Int               // 分類 id (-1 = 常用詞)
    let n: String            // name
    let c: Int               // number of words
}

struct WidgetState: Codable {
    var rom = 0
    var place = -1
    var saved: [String] = []
    var known: [String] = []
    /// how solid the widget background is (0 = see-through, 1 = solid); 設定 → 小工具
    var bg: Double? = nil
}

/// a 收藏 change made on the widget: the app applies it the next time it's opened
struct WidgetInboxOp: Codable {
    let k: String
    let save: Bool
    let t: Double
    /// true = "I know this word" (✓ on the widget): the app moves it to 熟悉
    var known: Bool? = nil
}

enum WidgetShared {
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "FFAppGroup") as? String) ?? "group.com.unoki99.fangfangcards"
    }
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget", isDirectory: true)
    }
    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func url(_ name: String) -> URL? {
        guard let f = folder else { return nil }
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f.appendingPathComponent(name)
    }
    static func categoryFile(_ id: Int) -> String { "words-\(id).json" }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let u = url(name), let d = try? JSONEncoder().encode(value) else { return }
        try? d.write(to: u, options: .atomic)
    }

    static func categories() -> [WidgetCategory] { read([WidgetCategory].self, "categories.json") ?? [] }
    static func words(_ cat: Int) -> [WidgetWord] { read([WidgetWord].self, categoryFile(cat)) ?? [] }
    static func state() -> WidgetState { read(WidgetState.self, "state.json") ?? WidgetState() }
    static func inbox() -> [WidgetInboxOp] { read([WidgetInboxOp].self, "inbox.json") ?? [] }

    /// saved words as the widget should show them: the app's list plus changes made on the widget
    static func savedNow() -> Set<String> {
        var s = Set(state().saved)
        for op in inbox() where op.known == nil { if op.save { s.insert(op.k) } else { s.remove(op.k) } }
        return s
    }

    /// 熟悉 words as the widget should see them: the app's list plus ✓ pressed on the widget
    static func knownNow() -> Set<String> {
        var s = Set(state().known)
        for op in inbox() {
            if op.known == true { s.insert(op.k) } else if op.known == false { s.remove(op.k) }
        }
        return s
    }

    /// ✓ on the widget: known ↔ not known (pressing it again takes it back)
    static func toggleKnownFromWidget(_ key: String) {
        let known = !knownNow().contains(key)
        var ops = inbox()
        ops.append(WidgetInboxOp(k: key, save: false, t: Date().timeIntervalSince1970, known: known))
        write(ops, "inbox.json")
    }

    /// the word on show for a 分類 stays until the next hour or →, even after ✓ (it just won't come back later)
    static func pinned(_ cat: Int, slot: String) -> String? {
        guard let v = defaults?.string(forKey: "pin-\(cat)"), v.hasPrefix(slot + "|") else { return nil }
        return String(v.dropFirst(slot.count + 1))
    }
    static func pin(_ cat: Int, slot: String, key: String) { defaults?.set(slot + "|" + key, forKey: "pin-\(cat)") }

    static func toggleSavedFromWidget(_ key: String) {
        let save = !savedNow().contains(key)
        var ops = inbox()
        ops.append(WidgetInboxOp(k: key, save: save, t: Date().timeIntervalSince1970))
        write(ops, "inbox.json")
    }

    /// the same recording paths as the app (Audio.wordPath / examplePath)
    static func wordPath(_ id: Int) -> String { "audio/\(id / 1000)/\(id)(1).mp3" }
    static func examplePath(_ name: String) -> String {
        let id = Int(name.split(separator: "-").first ?? "0") ?? 0
        return "leku/\(id / 1000)/\(name).mp3"
    }

    /// "→ next word": counts per 分類
    static func nextCount(_ cat: Int) -> Int { defaults?.integer(forKey: "next-\(cat)") ?? 0 }
    static func bumpNext(_ cat: Int) { defaults?.set(nextCount(cat) + 1, forKey: "next-\(cat)") }
}

// MARK: widget buttons

/// ▶ on the widget: the app plays the recording in the background (needs the "audio" background mode)
struct PlayWidgetAudioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "播放發音"
    static let isDiscoverable = false
    @Parameter(title: "音檔") var path: String
    init() {}
    init(path: String) { self.path = path }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        Player.shared.play(path)
        try? await Task.sleep(nanoseconds: 300_000_000)
        for _ in 0..<50 {                       // stay until the recording has played
            if Player.shared.playing != path { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        return .result()
    }
}

/// 收藏 on the widget
struct ToggleWidgetSaveIntent: AppIntent {
    static let title: LocalizedStringResource = "收藏／取消收藏"
    static let isDiscoverable = false
    @Parameter(title: "詞") var key: String
    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        WidgetShared.toggleSavedFromWidget(key)
        return .result()
    }
}

/// ✓ on the widget: I know this word (moves to 熟悉 and won't come up again; press again to take it back)
struct MarkWidgetKnownIntent: AppIntent {
    static let title: LocalizedStringResource = "標成熟悉"
    static let isDiscoverable = false
    @Parameter(title: "詞") var key: String
    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        WidgetShared.toggleKnownFromWidget(key)
        return .result()
    }
}

/// → on the widget: another word from the same 分類
struct NextWidgetWordIntent: AppIntent {
    static let title: LocalizedStringResource = "下一個詞"
    static let isDiscoverable = false
    @Parameter(title: "分類") var category: Int
    init() {}
    init(category: Int) { self.category = category }

    func perform() async throws -> some IntentResult {
        WidgetShared.bumpNext(category)
        return .result()
    }
}
