import Foundation
import SwiftUI
import WidgetKit

/// Keeps the 分類 widgets up to date: writes each 分類's words (in the chosen spelling and 腔口) and your
/// progress into the App Group folder, and takes over words saved on a widget.
@MainActor
enum WidgetBridge {
    /// words shown for 常用詞 (the widget's "all words" choice): the most common ones
    static let commonCount = 1000
    private static var building = false
    private static var stateTask: Task<Void, Never>?

    /// call when the app opens: apply the widget's 收藏 changes, then refresh what the widget shows
    static func appOpened(_ store: Store) {
        guard store.loaded, WidgetShared.folder != nil else { return }
        mergeInbox(store)
        writeState(store)
        rebuildIfNeeded(store)
    }

    /// 收藏 changes made on a widget → the app's 收藏
    static func mergeInbox(_ store: Store) {
        let ops = WidgetShared.inbox()
        guard !ops.isEmpty else { return }
        for op in ops {
            if op.known == true {
                if let c = store.byKey[op.k], store.status(c) != 1 { store.mark(c, known: true, undoable: false) }
            } else if op.known == false {
                // ✓ taken back on the widget: back to 新詞
                if let c = store.byKey[op.k], store.status(c) == 1 { store.forget(c) }
            } else if store.isSaved(op.k) != op.save {
                store.toggleSaved(op.k)
            }
        }
        WidgetShared.write([WidgetInboxOp](), "inbox.json")
        store.saveNow()
    }

    /// progress or settings changed: a moment later, write what the widget needs to know
    static func progressChanged(_ store: Store) {
        stateTask?.cancel()
        stateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            writeState(store)
        }
    }

    static func writeState(_ store: Store) {
        guard store.loaded, WidgetShared.folder != nil else { return }
        let d = UserDefaults.standard
        var st = WidgetState()
        st.rom = min(max(d.integer(forKey: "rom"), 0), 2)
        st.place = d.object(forKey: "place") as? Int ?? -1
        st.bg = d.object(forKey: "widgetBG") as? Double ?? 0.45
        st.saved = store.progress.saved.filter { $0.value > 0 }.map(\.key).sorted()
        st.known = store.progress.status.filter { $0.value == 1 }.map(\.key).sorted()
        // don't drop saves made on the widget that the app hasn't taken over yet
        if !WidgetShared.inbox().isEmpty { mergeInbox(store); st.saved = store.progress.saved.filter { $0.value > 0 }.map(\.key).sorted() }
        WidgetShared.write(st, "state.json")
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// the word files: written again when the 腔口 changes, the dictionary has loaded (for local readings
    /// in the example sentences), or the word list changed
    static func rebuildIfNeeded(_ store: Store) {
        guard store.loaded, !building, WidgetShared.folder != nil else { return }
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        if place >= 0 && store.dict == nil { store.loadDict() }    // finished later: called again then
        let tones = ToneColors.system
        if tones != 0 && store.dict == nil { store.loadDict() }    // tone colours need the dictionary: called again then
        let needsDict = place >= 0 || tones != 0
        let stamp = "v2|\(store.cards.count)|\(store.cards.first?.k ?? "")|\(place)|\(needsDict && store.dict != nil)|\(tones)|\(ToneColors.marks)"
        if WidgetShared.defaults?.string(forKey: "words-stamp") == stamp,
           WidgetShared.read([WidgetCategory].self, "categories.json") != nil { return }
        building = true
        Task { @MainActor in
            var byCat: [Int: [WidgetWord]] = [:]
            var common: [WidgetWord] = []
            for (i, c) in store.cards.enumerated() {
                if i % 150 == 0 { await Task.yield() }
                let cats = c.cats ?? []
                guard !cats.isEmpty || i < commonCount else { continue }
                let w = word(store, c, place)
                for cat in cats { byCat[cat, default: []].append(w) }
                if i < commonCount { common.append(w) }
            }
            var list = [WidgetCategory(i: -1, n: "常用詞", c: common.count)]
            WidgetShared.write(common, WidgetShared.categoryFile(-1))
            for t in store.topics {
                guard let ws = byCat[t.id], !ws.isEmpty else { continue }
                WidgetShared.write(ws, WidgetShared.categoryFile(t.id))
                list.append(WidgetCategory(i: t.id, n: t.name, c: ws.count))
            }
            WidgetShared.write(list, "categories.json")
            WidgetShared.defaults?.set(stamp, forKey: "words-stamp")
            WidgetCenter.shared.reloadAllTimelines()
            building = false
            rebuildIfNeeded(store)          // the 腔口 or the dictionary changed meanwhile: once more
        }
    }

    /// one card as a widget word: the meaning that has an example sentence (so they match), in all spellings
    private static func word(_ store: Store, _ c: Card, _ place: Int) -> WidgetWord {
        let def = c.d.first(where: { !$0.x.isEmpty }) ?? c.d.first
        let x = def?.x.first
        let plain: (AttributedString) -> String = { String($0.characters) }
        let han = store.cardHan(c, place, base: T.blueInk)
        let rom = (0..<3).map { store.cardRom(c, $0, place) }
        let zy = store.cardZy(c, place)
        let xh = x.map { store.exampleHan(c, $0, place) }
        let xr = x.map { ex in (0..<3).map { store.exampleRom(c, ex, $0, place) } }
        var w = WidgetWord(
            k: c.k, h: c.h, a: c.a,
            r: rom.map(plain),
            z: plain(zy),
            p: def?.p ?? "", m: def?.t ?? "",
            xh: xh.map(plain),
            xr: xr.map { $0.map(plain) },
            xz: x?.z, xn: x?.n)
        w.hc = segs(han); w.rc = rom.map(segs); w.zc = segs(zy)
        w.xhc = xh.map(segs); w.xrc = xr.map { $0.map(segs) }
        return w
    }

    /// an AttributedString as pieces of one colour each (for the widget, which can't read SwiftUI colours)
    private static func segs(_ a: AttributedString) -> [WSeg] {
        var out: [WSeg] = []
        let env = EnvironmentValues()
        for run in a.runs {
            let t = String(a[run.range].characters)
            var hex: String? = nil
            if let col = run.swiftUI.foregroundColor {
                let r = col.resolve(in: env)
                hex = String(format: "%02x%02x%02x", Int((r.red * 255).rounded()), Int((r.green * 255).rounded()), Int((r.blue * 255).rounded()))
            }
            if let last = out.last, last.c == hex { out[out.count - 1] = WSeg(t: last.t + t, c: hex) }
            else { out.append(WSeg(t: t, c: hex)) }
        }
        return out
    }
}
