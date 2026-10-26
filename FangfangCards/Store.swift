import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var progress = Progress() {
        didSet { recount() }
    }
    // counted once per change instead of on every screen redraw
    private(set) var seenCount = 0
    private(set) var unknownCount = 0
    private(set) var knownCount = 0
    private var newStart = 0          // every card before this index has been seen
    private var saveTask: Task<Void, Never>?
    @Published private(set) var canUndo = false
    @Published var backupFolderName: String?
    @Published var lastBackup: Date?

    private(set) var byKey: [String: Card] = [:]
    /// the full dictionary for 轉換 (loaded in the background the first time it's needed)
    @Published private(set) var dict: Dict?
    @Published private(set) var dictError: String?
    private var dictLoading = false
    private(set) var syl: [String: [String]] = [:]
    private(set) var places: [String] = []
    private(set) var topics: [Topic] = []
    private var rank: [String: Int] = [:]
    private var pools: [Int: [Card]] = [:]          // common words by syllable count, for wrong answers
    private var undoStack: [(key: String, status: Int?, added: Double?, streak: Int?)] = []

    private var progressURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("progress.json")
    }

    // MARK: loading

    func load() {
        guard !loaded else { return }
        guard let url = Bundle.main.url(forResource: "cards", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            loadError = "找不到 cards.json"; return
        }
        do {
            let deck = try JSONDecoder().decode(DeckFile.self, from: data)
            cards = deck.cards
            syl = deck.syl ?? [:]
            places = deck.places ?? []
            topics = deck.topics ?? []
        } catch {
            loadError = "字典讀取失敗：\(error.localizedDescription)"; return
        }
        for (i, c) in cards.enumerated() {
            byKey[c.k] = c
            rank[c.k] = i
        }
        for c in cards.prefix(4000) { pools[c.syllables, default: []].append(c) }
        if let d = try? Data(contentsOf: progressURL),
           let p = try? JSONDecoder().decode(Progress.self, from: d) {
            progress = p
        }
        loaded = true
        // with a place chosen, example sentences use the dictionary to find each word's local reading
        if (UserDefaults.standard.object(forKey: "place") as? Int ?? -1) >= 0 { loadDict() }
        restoreBackupState()
        syncNow()
    }

    /// saves a moment later, off the main thread, so swiping never waits for the disk
    func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self, self.loaded,
                  let d = try? JSONEncoder().encode(self.progress) else { return }
            let url = self.progressURL
            await Task.detached { try? d.write(to: url, options: .atomic) }.value
        }
    }

    /// immediate save (when the app goes to the background)
    func saveNow() {
        saveTask?.cancel()
        guard loaded, let d = try? JSONEncoder().encode(progress) else { return }
        try? d.write(to: progressURL, options: .atomic)
    }

    private func recount() {
        var s = 0, u = 0, k = 0
        for v in progress.status.values {
            if v != 0 { s += 1 }
            if v == 1 { k += 1 } else if v == 2 { u += 1 }
        }
        seenCount = s; unknownCount = u; knownCount = k
        newStart = 0
    }

    // MARK: lists

    func status(_ c: Card) -> Int? { progress.status[c.k] }
    func streak(_ c: Card) -> Int { progress.streak[c.k] ?? 0 }

    /// next unseen words, most common first
    private var queueTopic = -1
    /// next unseen words, most common first; topic = a 分類 index or -1 for everything
    func newQueue(_ n: Int, topic: Int = -1) -> [Card] {
        if topic != queueTopic { queueTopic = topic; newStart = 0 }
        var out: [Card] = []
        var i = newStart
        var first: Int?
        while i < cards.count && out.count < n {
            if (progress.status[cards[i].k] ?? 0) == 0 && (topic < 0 || cards[i].cats?.contains(topic) == true) {
                if first == nil { first = i }
                out.append(cards[i])
            }
            i += 1
        }
        newStart = first ?? cards.count
        return out
    }

    /// newest first
    private func list(_ s: Int) -> [Card] {
        progress.status.compactMap { $0.value == s ? byKey[$0.key] : nil }
            .sorted { (progress.added[$0.k] ?? 0) > (progress.added[$1.k] ?? 0) }
    }
    var unknownCards: [Card] { list(2) }
    var knownCards: [Card] { list(1) }

    // MARK: changes

    /// swipe: right = known, left = unknown
    func mark(_ c: Card, known: Bool, undoable: Bool = true) {
        if undoable {
            undoStack.append((c.k, progress.status[c.k], progress.added[c.k], progress.streak[c.k]))
            if undoStack.count > 50 { undoStack.removeFirst() }
            canUndo = true
        }
        progress.status[c.k] = known ? 1 : 2
        progress.added[c.k] = Date().timeIntervalSince1970
        if known { progress.streak[c.k] = nil } else if progress.streak[c.k] == nil { progress.streak[c.k] = 0 }
        save()
    }

    func undo() {
        guard let u = undoStack.popLast() else { return }
        progress.status[u.key] = u.status
        progress.added[u.key] = u.added
        progress.streak[u.key] = u.streak
        canUndo = !undoStack.isEmpty
        save()
    }

    /// back to the new-word pile (kept as status 0 so other devices learn about it when syncing)
    func forget(_ c: Card) {
        progress.status[c.k] = 0
        progress.added[c.k] = Date().timeIntervalSince1970
        progress.streak[c.k] = nil
        save()
    }

    /// study answer; returns true when the word has been learned (moved to 熟悉)
    @discardableResult
    func answer(_ c: Card, correct: Bool, goal: Int) -> Bool {
        guard progress.status[c.k] == 2 else { return false }
        if correct {
            let s = (progress.streak[c.k] ?? 0) + 1
            if s >= goal {
                progress.status[c.k] = 1
                progress.added[c.k] = Date().timeIntervalSince1970
                progress.streak[c.k] = nil
                save()
                return true
            }
            progress.streak[c.k] = s
        } else {
            progress.streak[c.k] = 0
        }
        save()
        return false
    }

    /// words starred (☆) in the 轉換 tab go to 不熟 (unless switched off in 設定)
    func addFromConverter(_ saved: [String]) {
        guard loaded, UserDefaults.standard.object(forKey: "convSync") as? Bool ?? true else { return }
        let now = Date().timeIntervalSince1970
        var n = 0
        for s in saved {
            let k = s.split(separator: "\t", omittingEmptySubsequences: false).prefix(2).joined(separator: "\t")
            guard byKey[k] != nil, (progress.status[k] ?? 0) == 0 else { continue }
            progress.status[k] = 2
            progress.added[k] = now
            progress.streak[k] = 0
            n += 1
        }
        if n > 0 { save() }
    }

    func loadDict() {
        guard dict == nil, !dictLoading else { return }
        dictLoading = true
        Task {
            let result: Result<Dict, Error> = await Task.detached(priority: .userInitiated) { () -> Result<Dict, Error> in
                do {
                    guard let url = Bundle.main.url(forResource: "dict", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
                    let data = try Data(contentsOf: url)
                    return .success(Dict(try JSONDecoder().decode(DictRaw.self, from: data)))
                } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let d): self.dict = d
            case .failure(let e): self.dictError = "字典讀取失敗：\(e.localizedDescription)"
            }
            self.dictLoading = false
        }
    }

    /// a card's reading, with syllables guessed for the place in blue
    func cardRom(_ card: Card, _ rom: Int, _ place: Int) -> AttributedString {
        let r = min(max(rom, 0), 2)
        if place >= 0, let d = dict, !d.guessedSyllables(card.k, place).isEmpty { return d.wordText(card.k, r, place) }
        return AttributedString(card.rom(r, place))
    }
    func cardZy(_ card: Card, _ place: Int) -> AttributedString {
        if place >= 0, let d = dict, !d.guessedSyllables(card.k, place).isEmpty { return d.wordText(card.k, 3, place) }
        return AttributedString(card.zy(place))
    }

    /// a card's example in 羅馬字, in the chosen place's readings when the dictionary is loaded
    /// (guessed readings are blue)
    func exampleRom(_ card: Card, _ x: Example, _ rom: Int, _ place: Int) -> AttributedString {
        let r = min(max(rom, 0), 2)
        guard place >= 0, let d = dict, let e = dictExample(d, card, x) else { return AttributedString(x.r[r]) }
        return d.sentenceText(e[1], r, place: place, han: e[0])
    }

    /// 例句填空: the example with the word blanked out, in the chosen place's readings
    func blankRom(_ card: Card, _ x: Example, _ rom: Int, _ place: Int) -> AttributedString? {
        let r = min(max(rom, 0), 2)
        if place >= 0, let d = dict, let e = dictExample(d, card, x),
           let ps = d.blankSentencePieces(e[1], han: e[0], word: Dict.codesOf(card.k).split(separator: " ").map(String.init), r, place: place) {
            return guessColored(ps)
        }
        return x.br.map { AttributedString($0[r]) }
    }

    /// does any example of this card have a guessed reading for the place?
    func cardHasGuess(_ card: Card, _ place: Int) -> Bool {
        guard place >= 0, let d = dict else { return false }
        return card.d.contains { $0.x.contains { x in dictExample(d, card, x).map { d.hasGuess($0[1], han: $0[0], place: place) } ?? false } }
    }

    private func dictExample(_ d: Dict, _ card: Card, _ x: Example) -> [String]? {
        d.raw.ex[card.k]?.joined().first(where: { $0.count > 3 && $0[0] == x.h && $0[3] == x.n })
    }

    /// the card's own reading for the place is worked out by rule, not stated by the dictionary
    func isGuessed(_ card: Card, _ place: Int) -> Bool {
        guard place >= 0, card.differs(in: place), let d = dict else { return false }
        return !d.isStated(card.k, place)
    }

    /// status of a dictionary word in the cards: nil = not a card
    func cardStatus(_ key: String) -> Int? {
        guard byKey[key] != nil else { return nil }
        return progress.status[key] ?? 0
    }

    /// ☆ in 轉換: add to 不熟, or tap again to take it back out to 新詞
    func toggleUnknown(_ key: String) {
        guard let c = byKey[key] else { return }
        if progress.status[key] == 2 { forget(c) } else { mark(c, known: false, undoable: false) }
    }

    // MARK: 收藏 (轉換)

    func isSaved(_ key: String) -> Bool { (progress.saved[key] ?? -1) > 0 }

    func toggleSaved(_ key: String) {
        let now = Date().timeIntervalSince1970
        progress.saved[key] = isSaved(key) ? -now : now
        save()
    }

    /// how common a word is (its place in the card order)
    func rankOf(_ key: String) -> Int { rank[key] ?? Int.max }

    /// words not yet seen go to 不熟 (words already in 不熟 / 熟悉 stay where they are)
    func addUnknown(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        var n = 0
        for k in keys where byKey[k] != nil && (progress.status[k] ?? 0) == 0 {
            progress.status[k] = 2
            progress.added[k] = now
            progress.streak[k] = 0
            n += 1
        }
        if n > 0 { save() }
    }

    func saveAll(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        for (i, k) in keys.enumerated() where !isSaved(k) { progress.saved[k] = now + Double(keys.count - i) * 0.001 }
        save()
    }

    func unsave(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        for k in keys { progress.saved[k] = -now }
        save()
    }

    /// saved words, newest first
    var savedKeys: [String] {
        progress.saved.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { $0.key }
    }

    /// 收藏 as the same nine-column CSV
    func savedCSV(_ d: Dict) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var rows = ["詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔"]
        for k in savedKeys {
            let h = Dict.hanOf(k), r = d.word(k, 0, -1)
            let audio = d.raw.au[k].map { "\($0)(1)" } ?? ""
            let senses = d.senses(k)
            if senses.isEmpty { rows.append([h, r, "", "", "", "", "", audio, ""].map(q).joined(separator: ";")) }
            for s in senses {
                let x = s.ex.first
                rows.append([h, r, s.pos, s.text, x?[0] ?? "", x.map { $0.count > 1 ? d.sentence($0[1], 0) : "" } ?? "",
                             x.map { $0.count > 2 ? $0[2] : "" } ?? "", audio, x.map { $0.count > 3 ? $0[3] : "" } ?? ""]
                    .map(q).joined(separator: ";"))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }

    /// every word back to 新詞 (stamped with the time, so synced devices reset too)
    func resetAll() {
        let now = Date().timeIntervalSince1970
        var p = Progress()
        for k in progress.status.keys { p.status[k] = 0; p.added[k] = now }
        progress = p
        undoStack = []
        canUndo = false
        save()
    }

    // MARK: study helpers

    /// wrong answers for a multiple-choice question
    func distractors(for c: Card, count: Int = 3) -> [Card] {
        var pool = pools[c.syllables] ?? []
        if pool.count < 20 { pool = Array(cards.prefix(4000)) }
        var out: [Card] = []
        var usedH: Set<String> = [c.h], usedM: Set<String> = [c.firstMeaning], usedR: Set<String> = [c.r[0]]
        var tries = 0
        while out.count < count && tries < 200 {
            tries += 1
            guard let x = pool.randomElement() else { break }
            if usedH.contains(x.h) || usedM.contains(x.firstMeaning) || usedR.contains(x.r[0]) { continue }
            usedH.insert(x.h); usedM.insert(x.firstMeaning); usedR.insert(x.r[0])
            out.append(x)
        }
        return out
    }

    // MARK: export / import

    /// nine columns, semicolon separated, one row per meaning (same as the website's 收藏 CSV)
    func csv(_ list: [Card]) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var rows = ["詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔"]
        for c in list {
            for d in c.d {
                let x = d.x.first
                let audio = c.a.map { "\($0)(1)" } ?? ""
                rows.append([c.h, c.r[0], d.p, d.t, x?.h ?? "", x?.r[0] ?? "", x?.z ?? "", audio, x?.n ?? ""]
                    .map(q).joined(separator: ";"))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }

    /// Merge another device's / an older backup's progress: for each word the newer change wins.
    /// Returns how many words changed.
    func mergeProgress(_ obj: [String: Any]) -> Int {
        let status = obj["status"] as? [String: Int] ?? [:]
        let added = obj["added"] as? [String: Double] ?? [:]
        let streak = obj["streak"] as? [String: Int] ?? [:]
        var n = 0
        for (k, t) in obj["saved"] as? [String: Double] ?? [:] where abs(t) > abs(progress.saved[k] ?? 0) {
            if (t > 0) != isSaved(k) { n += 1 }
            progress.saved[k] = t
        }
        for (k, s) in status where byKey[k] != nil {
            let theirs = added[k] ?? 0, mine = progress.added[k] ?? -1
            if theirs > mine || (progress.status[k] == nil && theirs >= mine) {
                if progress.status[k] != s { n += 1 }
                progress.status[k] = s
                progress.added[k] = theirs
                progress.streak[k] = s == 2 ? max(streak[k] ?? 0, progress.streak[k] ?? 0) : nil
            } else if s == 2, progress.status[k] == 2, let t = streak[k], t > (progress.streak[k] ?? 0), theirs == mine {
                progress.streak[k] = t
            }
        }
        return n
    }

    func backupData() -> Data {
        let obj: [String: Any] = [
            "app": "fangfang-cards", "version": 1,
            "exported": ISO8601DateFormatter().string(from: Date()),
            "status": progress.status, "added": progress.added, "streak": progress.streak,
            "saved": progress.saved,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Accepts this app's backup, or a 方方 website / Safari extension backup
    /// (its saved words are added to 不熟). Returns a message for the user.
    func importBackup(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "讀不到這個檔案。"
        }
        let app = obj["app"] as? String
        if app == "fangfang-cards" {
            let n = mergeProgress(obj)
            save()
            return "已匯入，更新了 \(n) 個詞。"
        }
        if app == "fangfang", let saved = obj["saved"] as? [String] {
            var n = 0, m = 0
            let now = Date().timeIntervalSince1970
            for s in saved {
                let k = s.split(separator: "\t", omittingEmptySubsequences: false).prefix(2).joined(separator: "\t")
                if !isSaved(k) { progress.saved[k] = now; m += 1 }
                guard byKey[k] != nil, progress.status[k] != 2 else { continue }
                progress.status[k] = 2
                progress.added[k] = now
                progress.streak[k] = 0
                n += 1
            }
            save()
            return "已把方方收藏的 \(m) 個詞加到「轉換 → 收藏」，\(n) 個詞加到「不熟」。"
        }
        return "這不是方方的備份檔。"
    }
}
