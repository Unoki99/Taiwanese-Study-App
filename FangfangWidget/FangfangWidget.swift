import WidgetKit
import SwiftUI
import AppIntents

// 分類詞卡: a word from the 分類 you pick, with its meaning, an example sentence, ▶ and 收藏.
// Large (4×4) and medium (4×2). A new word every hour; → for another one.

@main
struct FangfangWidgets: WidgetBundle {
    var body: some Widget { FangfangWordWidget() }
}

struct FangfangWordWidget: Widget {
    let kind = "FangfangWordWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WordWidgetIntent.self, provider: WordProvider()) { entry in
            WordWidgetView(entry: entry)
        }
        .configurationDisplayName("分類詞卡")
        .description("從你選的分類看詞、意思和例句，可以聽發音、收藏。每個鐘頭換一個詞。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: choosing the 分類

struct CategoryEntity: AppEntity {
    let id: Int
    let name: String
    let count: Int
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "分類"
    static let defaultQuery = CategoryQuery()
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(count) 個詞")
    }
    init(_ c: WidgetCategory) { id = c.i; name = c.n; count = c.c }
}

struct CategoryQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [CategoryEntity] {
        WidgetShared.categories().filter { identifiers.contains($0.i) }.map(CategoryEntity.init)
    }
    func entities(matching string: String) async throws -> [CategoryEntity] {
        WidgetShared.categories().filter { $0.n.contains(string) }.map(CategoryEntity.init)
    }
    func suggestedEntities() async throws -> [CategoryEntity] {
        WidgetShared.categories().map(CategoryEntity.init)
    }
    func defaultResult() async -> CategoryEntity? {
        WidgetShared.categories().first.map(CategoryEntity.init)
    }
}

struct WordWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "分類詞卡"
    static let description = IntentDescription("選一個分類，小工具會顯示裡面的詞（「熟悉」的詞不會出現）。")
    @Parameter(title: "分類") var category: CategoryEntity?
    init() {}
}

// MARK: which word

struct WordEntry: TimelineEntry {
    let date: Date
    let word: WidgetWord?
    let category: Int
    let categoryName: String
    let rom: Int
    let saved: Bool
    var known = false
    var empty: String? = nil
    var bg: Double = 0.45
}

struct WordProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WordEntry {
        WordEntry(date: Date(), word: WordProvider.sample, category: -1, categoryName: "常用詞", rom: 0, saved: false)
    }

    func snapshot(for configuration: WordWidgetIntent, in context: Context) async -> WordEntry {
        let e = entry(configuration, Date())
        return e.word == nil && context.isPreview ? placeholder(in: context) : e
    }

    func timeline(for configuration: WordWidgetIntent, in context: Context) async -> Timeline<WordEntry> {
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        var entries = [entry(configuration, now)]
        for h in 1...6 {
            entries.append(entry(configuration, hour.addingTimeInterval(Double(h) * 3600)))
        }
        return Timeline(entries: entries, policy: .after(hour.addingTimeInterval(6 * 3600)))
    }

    private func entry(_ config: WordWidgetIntent, _ date: Date) -> WordEntry {
        let cats = WidgetShared.categories()
        let catID = config.category?.id ?? cats.first?.i ?? -1
        let name = config.category?.name ?? cats.first(where: { $0.i == catID })?.n ?? "常用詞"
        let st = WidgetShared.state()
        let all = WidgetShared.words(catID)
        guard !all.isEmpty else {
            return WordEntry(date: date, word: nil, category: catID, categoryName: name, rom: st.rom, saved: false,
                             empty: "打開方方詞卡一次，小工具就會載入詞。", bg: st.bg ?? 0.45)
        }
        let known = WidgetShared.knownNow()
        let hourIndex = Int(date.timeIntervalSince1970 / 3600)
        let next = WidgetShared.nextCount(catID)
        let slot = "\(hourIndex)|\(next)"
        let isNow = hourIndex == Int(Date().timeIntervalSince1970 / 3600)
        // the word already on show stays (also right after ✓); a new one leaves out the 熟悉 words
        var w: WidgetWord
        if isNow, let k = WidgetShared.pinned(catID, slot: slot), let p = all.first(where: { $0.k == k }) {
            w = p
        } else {
            var pool = all.filter { !known.contains($0.k) }
            if pool.isEmpty { pool = all }                   // every word known: show them anyway
            let n = WordProvider.mix(UInt64(bitPattern: Int64(hourIndex)) &* 0x9E37_79B9
                                      &+ UInt64(bitPattern: Int64(catID)) &* 0x85EB_CA6B
                                      &+ UInt64(next) &* 0xC2B2_AE35)
            w = pool[Int(n % UInt64(pool.count))]
            if isNow { WidgetShared.pin(catID, slot: slot, key: w.k) }
        }
        return WordEntry(date: date, word: w, category: catID, categoryName: name, rom: st.rom,
                         saved: WidgetShared.savedNow().contains(w.k), known: known.contains(w.k), bg: st.bg ?? 0.45)
    }

    /// splitmix64: spreads the hour / → count over the whole list
    static func mix(_ x0: UInt64) -> UInt64 {
        var x = x0 &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    static let sample = WidgetWord(
        k: "食飯\tcia8 pNG7", h: "食飯", a: nil, r: ["jia̍h-pn̄g", "tsia̍h-pn̄g", "chia̍h-pn̄g"], z: "ㄐㄧㄚㆷ̇ ㄅㆭ˫",
        p: "動詞", m: "吃飯。", xh: "咱來去食飯。", xr: ["Lán lâi-khì jia̍h-pn̄g.", "Lán lâi-khì tsia̍h-pn̄g.", "Lán lâi-khì chia̍h-pn̄g."],
        xz: "我們去吃飯。", xn: nil,
        hc: [WSeg(t: "食", c: "ff8cc6"), WSeg(t: "飯", c: "ffe066")],
        rc: [[WSeg(t: "jia̍h", c: "ff8cc6"), WSeg(t: "-", c: nil), WSeg(t: "pn̄g", c: "ffe066")],
             [WSeg(t: "tsia̍h", c: "ff8cc6"), WSeg(t: "-", c: nil), WSeg(t: "pn̄g", c: "ffe066")],
             [WSeg(t: "chia̍h", c: "ff8cc6"), WSeg(t: "-", c: nil), WSeg(t: "pn̄g", c: "ffe066")]])
}
