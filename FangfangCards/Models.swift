import Foundation

/// One example sentence. `bh`/`br` are the fill-in-the-blank versions (word replaced by ＿＿).
struct Example: Decodable {
    let h: String          // 漢字
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 華語
    let n: String          // audio name, e.g. "3139-1-1"
    let bh: String?
    let br: [String]?
}

struct Def: Decodable {
    let p: String          // word class
    let t: String          // meaning
    let x: [Example]
    let sy: [[String]]?    // synonyms: [漢字, 皓羅]
    let an: [[String]]?    // antonyms
}

/// the word as said in one place (腔口)
struct Variant: Decodable {
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 方音
}

/// another reading: 又 / 俗 / 合
struct Other: Decodable {
    let l: String
    let r: [String]
    let z: String
}

struct Topic: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        id = try c.decode(Int.self)
        name = try c.decode(String.self)
        count = try c.decode(Int.self)
    }
}

struct Card: Decodable, Identifiable, Hashable {
    let k: String          // "漢字\tcodes" (same key as the website / extension)
    let h: String          // 漢字
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 方音
    let a: Int?            // MOE audio id
    let g: String          // 白 / 文 / 俗
    let d: [Def]
    let c: [String]?       // syllable codes
    let zo: String?        // 方音 when a place is chosen (Tâi-lô o shown as ㄛ)
    let v: [String: Variant]?   // place index -> reading there
    let o: [Other]?
    let s: Int?            // 1 = 替代字
    let t: String?         // 臺華共同 / 附錄
    let sy: [[String]]?
    let an: [[String]]?
    let cats: [Int]?

    var id: String { k }
    static func == (l: Card, r: Card) -> Bool { l.k == r.k }
    func hash(into h: inout Hasher) { h.combine(k) }

    /// reading in 皓羅 / 台羅 / 白話字 (i), in a place (-1 = 通行)
    func rom(_ i: Int, _ place: Int = -1) -> String {
        let j = min(max(i, 0), r.count - 1)
        if place >= 0, let x = v?[String(place)] { return x.r[min(j, x.r.count - 1)] }
        return r[j]
    }
    func zy(_ place: Int = -1) -> String {
        guard place >= 0 else { return z }
        if let x = v?[String(place)] { return x.z }
        return zo ?? z
    }
    func differs(in place: Int) -> Bool { place >= 0 && v?[String(place)] != nil }
    var syllables: Int { r[0].split(separator: "-").count }
    var firstMeaning: String { d.first?.t ?? "" }
    /// the meaning an example sentence belongs to (成 in 伊佮𪜶老爸生做誠成 → 相似, not 完成)
    func meaning(of x: Example) -> Def? { d.first { $0.x.contains { $0.n == x.n && $0.h == x.h } } }
    var blankExamples: [Example] { d.flatMap { $0.x }.filter { $0.bh != nil && $0.br != nil } }
    var firstExample: Example? { d.lazy.compactMap { $0.x.first }.first }
}

struct DeckFile: Decodable {
    let v: Int
    let cards: [Card]
    let syl: [String: [String]]?   // syllable code -> 皓羅, 台羅, 白話字 (incl. every tone, for 聲調練習)
    let places: [String]?
    let topics: [Topic]?
}

/// Saved progress. status: 1 = 熟悉 (known), 2 = 不熟 (unknown)
struct Progress: Codable {
    var status: [String: Int] = [:]
    var added: [String: Double] = [:]
    var streak: [String: Int] = [:]
    /// 收藏 in 轉換: key -> time saved (negative = removed, so synced devices remove it too)
    var saved: [String: Double] = [:]
    /// 自訂: words you added yourself (key -> time added; negative = removed, so synced devices remove it too)
    var own: [String: Double] = [:]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent([String: Int].self, forKey: .status) ?? [:]
        added = try c.decodeIfPresent([String: Double].self, forKey: .added) ?? [:]
        streak = try c.decodeIfPresent([String: Int].self, forKey: .streak) ?? [:]
        saved = try c.decodeIfPresent([String: Double].self, forKey: .saved) ?? [:]
        own = try c.decodeIfPresent([String: Double].self, forKey: .own) ?? [:]
    }
}

enum Audio {
    static let defaultBase = "https://unoki99.github.io/fangfang/"
    static func wordPath(_ id: Int) -> String { "audio/\(id / 1000)/\(id)(1).mp3" }
    static func examplePath(_ name: String) -> String {
        let id = Int(name.split(separator: "-").first ?? "0") ?? 0
        return "leku/\(id / 1000)/\(name).mp3"
    }
}
