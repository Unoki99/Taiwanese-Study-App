import SwiftUI
import UIKit

/// a dictionary word to open (key = "漢字\tcodes")
struct DictKey: Hashable, Identifiable {
    let k: String
    var id: String { k }
}

/// a category (分類) to list
struct CatRef: Hashable { let i: Int }

extension View {
    /// where dictionary words and categories open
    func dictDestinations(_ d: Dict) -> some View {
        navigationDestination(for: DictKey.self) { DictEntryView(dict: d, key: $0.k) }
            .navigationDestination(for: CatRef.self) { CategoryWordsView(dict: d, cat: $0.i) }
    }
}

/// shows its content once the dictionary is loaded
struct DictGate<Content: View>: View {
    @EnvironmentObject var store: Store
    @ViewBuilder let content: (Dict) -> Content
    var body: some View {
        Group {
            if let d = store.dict {
                content(d).dictDestinations(d)
            } else if let e = store.dictError {
                Text(e).foregroundStyle(T.muted).padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("載入字典…").font(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .onAppear { store.loadDict() }
    }
}

// MARK: - 轉換 tab

/// 轉換: 漢字 ⇄ 皓羅 ⇄ 方音, all native and offline (only audio uses the network).
struct ConverterView: View {
    var body: some View {
        DictGate { d in ConvertPane(dict: d) }
            .navigationTitle("轉換")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { RomButton() } }
    }
}

// MARK: - 詞典 tab

/// 詞典: look up 華語 / 台語 words, browse categories, saved words.
struct DictionaryView: View {
    var body: some View {
        DictGate { d in DictTabs(dict: d) }
            .navigationTitle("詞典")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { RomButton() } }
    }
}

/// 查詞 / 分類 / 收藏 (its own view, so switching always redraws the page below)
struct DictTabs: View {
    let dict: Dict
    @AppStorage("dictTab") private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("查詞").tag(0)
                Text("分類").tag(1)
                Text("收藏").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            Group {
                switch tab {
                case 1: CategoryPane(dict: dict)
                case 2: SavedPane(dict: dict)
                default: LookupPane(dict: dict)
                }
            }
            .id(tab)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - conversion

@MainActor
final class ConvModel: ObservableObject {
    @Published var text: String { didSet { schedule() } }
    @Published private(set) var result = ConvResult()
    @Published var latinMode: LatinMode {
        didSet {
            engine?.latinMode = latinMode
            UserDefaults.standard.set(latinMode.rawValue, forKey: "ff-latin")
            run()
        }
    }
    private(set) var engine: ConvertEngine?
    private var task: Task<Void, Never>?

    init() {
        text = UserDefaults.standard.string(forKey: "ff-text") ?? ""
        latinMode = LatinMode(rawValue: UserDefaults.standard.string(forKey: "ff-latin") ?? "") ?? .auto
    }

    func attach(_ d: Dict) {
        guard engine == nil else { return }
        let e = ConvertEngine(dict: d)
        e.latinMode = latinMode
        engine = e
        run()
    }

    private func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.run()
        }
    }

    func run() {
        guard let engine else { return }
        result = engine.convert(text)
        UserDefaults.standard.set(text, forKey: "ff-text")
    }

    func choose(_ item: Int, _ opt: Int) {
        guard result.items.indices.contains(item) else { return }
        result.items[item].sel = opt
        result.items[item].likely = nil          // your choice: no longer a guess
        engine?.remember(result.items, item)
    }
}

struct ConvertPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @StateObject private var model = ConvModel()
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @FocusState private var focused: Bool
    @State private var openItem: ConvSelection?
    @State private var copied: Int?

    private var hasOutput: Bool { model.result.items.contains(where: { $0.isWord }) }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 820 {
                // wide (iPad landscape, Mac): text on the left, the three scripts on the right
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            input
                            if model.result.anyLatin { latinPicker }
                            if hasOutput { actions } else { help }
                        }
                        .padding()
                    }
                    .frame(width: min(440, geo.size.width * 0.42))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasOutput { panels } else {
                                Text("轉換的結果會出現在這裡。").foregroundStyle(T.muted).padding(.top, 40)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .frame(maxWidth: 820)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        input
                        if model.result.anyLatin { latinPicker }
                        if hasOutput { panels; actions } else { help }
                    }
                    .padding()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { model.attach(dict) }
        #if targetEnvironment(macCatalyst)
        .navigationDestination(item: $openItem) { sel in
            WordSheet(dict: dict, model: model, index: sel.index, inSheet: false)
        }
        #else
        .sheet(item: $openItem) { sel in
            WordSheet(dict: dict, model: model, index: sel.index)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focused = false }
            }
        }
    }

    @ViewBuilder private var panels: some View {
        panel(0, "漢字")
        panel(1, ROM_NAMES[min(max(rom, 0), 2)])
        panel(2, "方音")
    }

    @ViewBuilder private var actions: some View {
        Button { copy(all: true) } label: {
            Label(copied == 9 ? "已複製" : "全部複製", systemImage: copied == 9 ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .softButton()
        let keys = textKeys
        if !keys.isEmpty {
            let newOnes = keys.filter { store.cardStatus($0) == 0 }
            Button { withAnimation(.snappy) { store.addUnknown(keys) } } label: {
                Label(newOnes.isEmpty ? "這段的新詞都在卡片裡了" : "這段的新詞加到「不熟」（\(newOnes.count)）",
                      systemImage: newOnes.isEmpty ? "star.fill" : "star")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
            .disabled(newOnes.isEmpty)
            let all = keys.allSatisfy { store.isSaved($0) }
            Button { withAnimation(.snappy) { store.saveAll(keys) } } label: {
                Label(all ? "這段的詞都收藏了" : "收藏這段所有的詞（\(keys.filter { !store.isSaved($0) }.count)）",
                      systemImage: all ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
            .disabled(all)
        }
        Text("點詞可以看意思、換讀音、收藏、加到「不熟」。有底色 = 已收藏或在「不熟」。橘色 = 字典裡找不到，或讀音不太確定（猜對的機會約 80% 以下），點一下可以確認。")
            .font(.caption).foregroundStyle(T.muted)
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text("輸入或貼上漢字、皓羅、方音、台羅、白話字…")
                    .foregroundStyle(T.muted)
                    .padding(.horizontal, 5).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 18))
                .frame(minHeight: 110, maxHeight: 220)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(8)
        .glassSurface(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Button {
                    if let s = UIPasteboard.general.string { model.text = s }
                } label: { Image(systemName: "doc.on.clipboard") }
                if !model.text.isEmpty {
                    Button { model.text = "" } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
            .font(.system(size: 18))
            .foregroundStyle(T.muted)
            .padding(10)
        }
    }

    private var latinPicker: some View {
        let autoName = ["lat": "皓羅", "tl": "台羅", "poj": "白話字"][model.result.autoLatin] ?? "皓羅"
        return VStack(alignment: .leading, spacing: 4) {
            Text("羅馬字當作").font(.caption).foregroundStyle(T.muted)
            Picker("羅馬字", selection: $model.latinMode) {
                Text("自動（\(autoName)）").tag(LatinMode.auto)
                Text("皓羅").tag(LatinMode.lat)
                Text("台羅").tag(LatinMode.tl)
                Text("白話字").tag(LatinMode.poj)
            }
            .pickerStyle(.segmented)
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("例：").font(.footnote.weight(.bold)).foregroundStyle(T.muted)
            ForEach(["我欲去學校讀冊。", "Guá beh khì ha̍k-hāu tha̍k-tsheh.", "ㆣㄨㄚˋ ㄅㆤㆷ ㄎㄧˋ"], id: \.self) { s in
                Button { model.text = s } label: {
                    Text(s).font(s.first.map { $0.isASCII } == true ? T.lat(16) : .body)
                        .foregroundStyle(T.glyph)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .softButton()
            }
        }
    }

    // MARK: output

    private func panel(_ mode: Int, _ title: String) -> some View {
        let pieces = model.engine?.pieces(model.result.items, mode: mode, rom: rom, place: place) ?? []
        let ink = [T.glyph, T.greenInk, T.purpleInk][mode]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(T.muted)
                Spacer()
                Button { copy(mode) } label: {
                    Image(systemName: copied == mode ? "checkmark" : "doc.on.doc").font(.footnote)
                }
                .foregroundStyle(T.muted)
            }
            Text(attributed(pieces, ink: ink, mode: mode))
                .font(mode == 1 ? T.lat(19) : .system(size: mode == 0 ? 22 : 20))
                .tint(ink)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "ff", let i = Int(url.lastPathComponent) {
                        focused = false
                        openItem = ConvSelection(index: i)
                    }
                    return .handled
                })
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18))
    }

    private func attributed(_ pieces: [(text: String, item: Int?)], ink: Color, mode: Int) -> AttributedString {
        var out = AttributedString()
        for p in pieces {
            var t = p.text
            if t.hasPrefix(" ") { out += AttributedString(" "); t.removeFirst() }
            var a = AttributedString(t)
            if let i = p.item {
                if i < 0 {
                    a.swiftUI.foregroundColor = .orange
                } else {
                    let it = model.result.items[i]
                    if it.current.codes == nil {
                        a.swiftUI.foregroundColor = .orange
                    } else {
                        var colored = false
                        if it.unsure { colored = true }                     // shaky guess: the whole word orange
                        else if mode != 0, let e = model.engine {
                            let ps = e.wordPieces(it.current, mode: mode, rom: rom, place: place)
                            if ps.contains(where: { $0.guessed }) { a = guessColored(ps, ink: ink); colored = true }
                        }
                        a.link = URL(string: "ff://w/\(i)")
                        if it.unsure { a.swiftUI.foregroundColor = .orange }
                        else if !colored { a.swiftUI.foregroundColor = ink }
                        if it.opts.count > 1 { a.swiftUI.underlineStyle = Text.LineStyle(pattern: .dot, color: (it.unsure ? Color.orange : ink).opacity(0.6)) }
                        if let k = dict.keyOf(it.current), store.isSaved(k) || store.cardStatus(k) == 2 {
                            a.swiftUI.backgroundColor = T.olive.opacity(0.85)
                        }
                    }
                }
            }
            out += a
        }
        return out
    }

    /// dictionary words in the converted text, in order, once each
    private var textKeys: [String] {
        var seen = Set<String>(), out: [String] = []
        for it in model.result.items where it.isWord && it.current.codes != nil {
            if let k = dict.keyOf(it.current), dict.raw.defs.m[k] != nil || dict.baseKeys.contains(k), seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    private func plain(_ mode: Int) -> String {
        (model.engine?.pieces(model.result.items, mode: mode, rom: rom, place: place) ?? []).map { $0.text }.joined()
    }

    private func copy(_ mode: Int) {
        UIPasteboard.general.string = plain(mode)
        flash(mode)
    }
    private func copy(all: Bool) {
        UIPasteboard.general.string = [plain(0), plain(1), plain(2)].joined(separator: "\n")
        flash(9)
    }
    private func flash(_ m: Int) {
        copied = m
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if copied == m { copied = nil } }
    }
}

struct ConvSelection: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

/// a word in the converted text: pick the reading, see its dictionary entry
struct WordSheet: View {
    let dict: Dict
    @ObservedObject var model: ConvModel
    let index: Int
    /// false on the Mac: shown as a page in the 轉換 tab instead of a sheet (sheets there have a fixed size)
    var inSheet = true
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if inSheet {
            NavigationStack {
                page
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
                        ToolbarItem(placement: .topBarLeading) { RomButton() }
                    }
                    .dictDestinations(dict)
            }
        } else {
            page
                .navigationTitle(model.result.items.indices.contains(index) ? (model.result.items[index].current.han ?? "") : "")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        }
    }

    private var page: some View {
            Group {
                if model.result.items.indices.contains(index) {
                    let it = model.result.items[index]
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 14) {
                            if it.opts.count > 1 { options(it) }
                            if let k = dict.keyOf(it.current), dict.baseKeys.contains(k) || dict.raw.defs.m[k] != nil {
                                DictEntryBody(dict: dict, key: k)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.engine?.wordText(it.current, mode: 0, rom: rom, place: place) ?? "")
                                        .font(.system(size: 30, weight: .semibold))
                                    if it.current.codes != nil {
                                        Text(optText(it.current, 1))
                                            .font(T.lat(20)).foregroundStyle(T.greenInk)
                                        Text(optText(it.current, 2))
                                            .foregroundStyle(T.purpleInk)
                                    }
                                    Text("字典裡沒有這個詞。").font(.footnote).foregroundStyle(T.muted)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
    }

    private func optText(_ o: Opt, _ mode: Int) -> AttributedString {
        guessColored(model.engine?.wordPieces(o, mode: mode, rom: rom, place: place) ?? [])
    }

    /// a short meaning for a reading choice: its 華語 words, or the start of its definition
    private func gloss(_ o: Opt) -> String? {
        guard let k = dict.keyOf(o) else { return nil }
        let pos = (dict.raw.pos[k] ?? "").split(separator: "|").first.map(String.init) ?? ""
        let text: String?
        if let g = dict.gl[k], !g.isEmpty { text = g.prefix(5).map { $0.t }.joined(separator: "、") }
        else if let t = dict.defText(k) {
            text = t.replacingOccurrences(of: #"\d+\.\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\n", with: "／")
        } else { text = nil }
        guard let t = text else { return nil }
        return pos.isEmpty ? t : "〔\(pos)〕" + t
    }

    private func options(_ it: ConvItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("選讀音／漢字").font(.caption.weight(.bold)).foregroundStyle(T.muted)
                if let p = it.likely {
                    Text("目前的讀音：猜對的機會約 \(Int((p * 100).rounded()))%")
                        .font(.caption).foregroundStyle(it.unsure ? Color.orange : T.muted)
                }
            }
            ForEach(Array(it.opts.enumerated()), id: \.offset) { i, o in
                Button {
                    withAnimation(.snappy) { model.choose(index, i) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: i == it.sel ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(i == it.sel ? T.greenInk : T.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(o.han ?? "—").font(.system(size: 20, weight: .semibold)).foregroundStyle(T.glyph)
                                if o.codes != nil {
                                    Text(optText(o, 1))
                                        .font(T.lat(17)).foregroundStyle(T.greenInk)
                                    Text(optText(o, 2))
                                        .font(.footnote).foregroundStyle(T.purpleInk)
                                }
                                if let l = o.label { Chip(text: l) }
                                if let k = dict.keyOf(o), let r = dict.raw.reg[k] { RegChip(reg: r) }
                            }
                            if let g = gloss(o) {
                                Text(g).font(.footnote).foregroundStyle(T.glyph.opacity(0.75))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 12).fill(i == it.sel ? T.green.opacity(0.6) : T.fn.opacity(0.6)))
            }
        }
    }
}

// MARK: - dictionary entry

struct DictEntryView: View {
    let dict: Dict
    let key: String
    var body: some View {
        ScrollView { DictEntryBody(dict: dict, key: key).padding().frame(maxWidth: 760).frame(maxWidth: .infinity) }
            .appBackground()
            .navigationTitle(Dict.hanOf(key))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

struct DictEntryBody: View {
    let dict: Dict
    let key: String
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    private var han: String { Dict.hanOf(key) }
    @State private var tapped: DictKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            let oth = dict.others(key, place)
            if !oth.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(oth.enumerated()), id: \.offset) { _, o in
                        OtherRow(label: o.label,
                                 rom: dict.codes(o.codes, rom, -1, tokens: o.tokens),
                                 zy: dict.codes(o.codes, 3, o.label == "通行" ? -1 : place, tokens: o.tokens))
                    }
                }
            }
            namesRow
            variantsRow
            categoriesRow
            if let g = dict.gl[key], !g.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Chip(text: "華語", fill: T.fn, edge: T.fnEdge, ink: T.muted)
                    Text(g.map { $0.t }.joined(separator: "、")).font(.subheadline).foregroundStyle(T.glyph.opacity(0.9))
                }
            }
            ForEach(dict.senses(key), id: \.n) { s in sense(s) }
            if place >= 0, dict.senses(key).contains(where: { s in s.ex.contains { $0.count > 1 && dict.hasGuess($0[1], han: $0[0], place: place) } }) {
                GuessNote()
            }
            let wl = dict.wordLinks(key)
            if !wl.syn.isEmpty || !wl.ant.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    links("近", wl.syn, T.blue, T.blueEdge, T.blueInk)
                    links("反", wl.ant, T.rust, T.rustEdge, T.rustInk)
                }
            }
            if dict.raw.typ[key] == 1 {
                Text("臺華共同詞：台語和華語寫法、意思一樣的詞。").font(.caption).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationDestination(item: $tapped) { DictEntryView(dict: dict, key: $0.k) }
    }

    /// the example's 漢字 with each dictionary word tappable (opens its entry)
    private func exampleHan(_ han: String, _ tpl: String) -> AttributedString {
        var out = AttributedString()
        for p in dict.exampleWords(han, tpl) {
            var a = AttributedString(p.text)
            if let k = p.key, k != key, let enc = k.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
               let url = URL(string: "ffword://w/" + enc) {
                a.link = url
                a.swiftUI.foregroundColor = T.blueInk
                a.swiftUI.underlineStyle = Text.LineStyle(pattern: .dot, color: T.blueInk.opacity(0.45))
            } else {
                a.swiftUI.foregroundColor = p.key == key ? T.oliveInk : T.glyph
            }
            out += a
        }
        return out
    }

    // MARK: parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(han).font(.system(size: 34, weight: .semibold)).foregroundStyle(T.glyph)
                if let au = dict.raw.au[key] { PlayButton(path: Audio.wordPath(au)) }
                Spacer()
            }
            HStack(spacing: 8) {
                saveButton
                star
            }
            Text(dict.wordText(key, rom, place)).font(T.lat(22)).foregroundStyle(T.greenInk).textSelection(.enabled)
            Text(dict.wordText(key, 3, place)).font(.system(size: 19)).foregroundStyle(T.purpleInk).textSelection(.enabled)
            HStack(spacing: 4) {
                if let r = dict.raw.reg[key] { RegChip(reg: r) }
                if dict.subst.contains(key) { Chip(text: "替", fill: T.rust, edge: T.rustEdge, ink: T.rustInk) }
                if let t = dict.raw.typ[key], t > 0, let types = dict.raw.types, t < types.count, t != 1 {
                    Chip(text: types[t], fill: T.fn, edge: T.fnEdge, ink: T.muted)
                }
                if dict.own.contains(key) { Chip(text: "方方補", fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                if place >= 0, dict.codesFor(key, place) != Dict.codesOf(key), place < dict.raw.places.count {
                    Chip(text: dict.raw.places[place], fill: Color(hex: 0x4c3a5b), edge: Color(hex: 0x7b3c9b), ink: T.purpleInk)
                    if !dict.isStated(key, place) { Chip(text: "推測", fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                }
            }
        }
    }

    private var saveButton: some View {
        let on = store.isSaved(key)
        return Button { withAnimation(.snappy) { store.toggleSaved(key) } } label: {
            Label(on ? "已收藏" : "收藏", systemImage: on ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? T.oliveInk : T.glyph)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? T.olive : T.fn.opacity(0.8)))
                .overlay(Capsule().stroke(on ? T.oliveEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var star: some View {
        if let st = store.cardStatus(key) {
            if st == 1 {
                Chip(text: "卡片：熟悉", fill: T.green, edge: T.greenEdge, ink: T.greenInk)
            } else {
                Button { withAnimation(.snappy) { store.toggleUnknown(key) } } label: {
                    Label(st == 2 ? "在「不熟」" : "加到「不熟」", systemImage: st == 2 ? "star.fill" : "star")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(st == 2 ? T.rustInk : T.glyph)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(st == 2 ? T.rust : T.fn.opacity(0.8)))
                        .overlay(Capsule().stroke(st == 2 ? T.rustEdge : T.fnEdge, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var namesRow: some View {
        if han.count == 1 {
            let part: (String, [[String]]?) -> String? = { lab, list in
                guard let list, !list.isEmpty else { return nil }
                return lab + "：" + list.prefix(4).map { dict.codes($0[0], rom, -1) }.joined(separator: "、")
            }
            let s = [part("人名", dict.raw.names[han]), part("姓", dict.raw.sur[han])].compactMap { $0 }.joined(separator: "　")
            if !s.isEmpty { Text(s).font(T.lat(14)).foregroundStyle(T.muted) }
        }
    }

    @ViewBuilder private var categoriesRow: some View {
        let cs = dict.raw.cat?[key] ?? []
        if !cs.isEmpty, let names = dict.raw.cats {
            HStack(alignment: .top, spacing: 6) {
                Chip(text: "分類", fill: T.pink, edge: T.pinkEdge, ink: T.pinkInk)
                FlowLayout(spacing: 6) {
                    ForEach(cs.filter { $0 < names.count }, id: \.self) { i in
                        NavigationLink(value: CatRef(i: i)) {
                            Text(names[i]).font(.subheadline).foregroundStyle(T.pinkInk)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(T.pink.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var variantsRow: some View {
        let vs = dict.raw.variants.filter { $0.value.contains(key) }.map(\.key).sorted()
        if !vs.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Chip(text: "異用字", fill: T.fn, edge: T.fnEdge, ink: T.muted)
                Text(vs.joined(separator: "、")).font(.subheadline).foregroundStyle(T.glyph.opacity(0.9))
            }
        }
    }

    private func sense(_ s: DictSense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s.n).").font(.subheadline.weight(.bold)).foregroundStyle(T.muted)
                if !s.pos.isEmpty { Chip(text: s.pos, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                Text(s.text).font(.body).foregroundStyle(T.glyph).textSelection(.enabled)
            }
            ForEach(Array(s.ex.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if e.count > 1 {
                            Text(exampleHan(e[0], e[1])).font(.body)
                                .environment(\.openURL, OpenURLAction { url in
                                    let prefix = "ffword://w/"
                                    if url.absoluteString.hasPrefix(prefix),
                                       let k = String(url.absoluteString.dropFirst(prefix.count)).removingPercentEncoding {
                                        tapped = DictKey(k: k)
                                    }
                                    return .handled
                                })
                        } else {
                            Text(e[0]).font(.body).foregroundStyle(T.glyph)
                        }
                        if e.count > 1 { Text(dict.sentenceText(e[1], rom, place: place, han: e[0])).font(T.lat(15)).foregroundStyle(T.greenInk) }
                        if e.count > 2, !e[2].isEmpty { Text(e[2]).font(.footnote).foregroundStyle(T.muted) }
                    }
                    .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if e.count > 3, !e[3].isEmpty { PlayButton(path: Audio.examplePath(e[3]), size: 28) }
                }
                .padding(.leading, 18)
            }
            if !s.syn.isEmpty || !s.ant.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    links("近", s.syn, T.blue, T.blueEdge, T.blueInk)
                    links("反", s.ant, T.rust, T.rustEdge, T.rustInk)
                }
                .padding(.leading, 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    @ViewBuilder private func links(_ name: String, _ keys: [String], _ fill: Color, _ edge: Color, _ ink: Color) -> some View {
        if !keys.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Chip(text: name, fill: fill, edge: edge, ink: ink)
                FlowLayout(spacing: 6) {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) {
                            HStack(spacing: 4) {
                                Text(Dict.hanOf(k)).foregroundStyle(T.glyph)
                                Text(dict.wordText(k, rom, place)).font(T.lat(13)).foregroundStyle(ink)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(fill.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// lays its children out in rows, wrapping like text
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > w { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing; row = max(row, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}

// MARK: - 華語 → 台語

struct LookupResult: Sendable {
    var exact: [String] = []
    var taigi: [String] = []         // words for a 台語 spelling (羅馬字 / 方音)
    var contains: [String] = []      // 台語 words that contain the 漢字
    var pattern: [String] = []       // 台語 words matching a * / ? pattern
    var patternZh: [String] = []     // 台語 words for 華語 words matching it
    var isPattern = false
    var gloss: [String] = []
    var defs: [String] = []
    var places: [(zh: String, rows: [(han: String, codes: String, places: [Int])])] = []
    var empty: Bool { taigi.isEmpty && contains.isEmpty && pattern.isEmpty && patternZh.isEmpty && exact.isEmpty && gloss.isEmpty && defs.isEmpty && places.isEmpty }
}

enum Lookup {
    /// * = one or more characters, ? = exactly one: 人* (starts with 人), *人 (ends with 人), *人* (人 in the middle), 一?一? …
    static func wildcard(_ d: Dict, _ q: String) -> LookupResult {
        var r = LookupResult()
        r.isPattern = true
        var pat = "^"
        for ch in q {
            switch ch {
            case "*", "＊": pat += ".+"
            case "?", "？": pat += "."
            default: pat += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        pat += "$"
        guard let re = try? NSRegularExpression(pattern: pat) else { return r }
        func hit(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        func rank(_ k: String) -> (Int, Double) { (Dict.hanOf(k).count, -d.score(Dict.hanOf(k), Dict.codesOf(k))) }
        // 台語 words
        var keys: [String] = []
        for (h, cs) in d.hanMap where hit(h) {
            for c in cs {
                let k = h + "\t" + c
                if d.baseKeys.contains(k) { keys.append(k) }
            }
        }
        r.pattern = Array(keys.sorted { rank($0) < rank($1) }.prefix(300))
        // 華語 words that match → their 台語 words
        let seen = Set(r.pattern)
        var zh: [String] = []
        for (t, ks) in d.termIndex where hit(t) { zh += ks.filter { !seen.contains($0) } }
        r.patternZh = Array(Set(zh).sorted { rank($0) < rank($1) }.prefix(100))
        return r
    }

    /// words for a 台語 spelling: 皓羅, 台羅, 白話字 (with or without tones; syllables split by space or -) or 方音
    static func taigi(_ d: Dict, _ q: String) -> [String] {
        var keys: [String] = [], seen = Set<String>()
        func add(_ h: String, _ codes: [String]) {
            guard let k = d.keyOf(Opt(han: h, codes: codes)), d.raw.defs.m[k] != nil || d.baseKeys.contains(k) else { return }
            if seen.insert(k).inserted { keys.append(k) }
        }
        if q.unicodeScalars.contains(where: { ConvertEngine.isZy($0.value) }) {
            // 方音: read it like the converter does
            let res = ConvertEngine(dict: d).convert(q)
            for it in res.items where it.isWord { for o in it.opts { if let h = o.han, let c = o.codes { add(h, c) } } }
        } else {
            let toks = q.precomposedStringWithCanonicalMapping
                .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "‑" || $0 == "　" }).map(String.init)
            var lists: [[String]] = []
            for t in toks {
                var c = Set<String>()
                let low = t.lowercased()
                c.formUnion(d.latRev[low] ?? [])
                if let rk = ConvertEngine.romKey(t) {
                    c.formUnion(d.tlRev[rk] ?? []); c.formUnion(d.pojRev[rk] ?? [])
                }
                let toned = t.decomposedStringWithCanonicalMapping.unicodeScalars.contains {
                    ((0x300...0x36F).contains($0.value) && $0.value != 0x358) || ("1"..."9").contains(Character($0))
                }
                if !toned { c.formUnion(d.plainRev[Dict.plainKey(t)] ?? []) }
                if c.isEmpty { return [] }
                lists.append(Array(c))
            }
            func combos(_ ls: ArraySlice<[String]>) -> [[String]] {
                var acc: [[String]] = [[]]
                for l in ls {
                    var next: [[String]] = []
                    outer: for a in acc { for x in l { next.append(a + [x]); if next.count >= 400 { break outer } } }
                    acc = next
                }
                return acc
            }
            for cs in combos(lists[...]) { for h in d.codeMap[cs.joined(separator: " ")] ?? [] { add(h, cs) } }
            // not one word: the words it's made of, longest first from the left
            if keys.isEmpty && lists.count > 1 {
                var i = 0
                while i < lists.count {
                    var step = 1
                    for L in stride(from: lists.count - i, through: 1, by: -1) {
                        var hit = false
                        for cs in combos(lists[i..<i + L]) {
                            for h in d.codeMap[cs.joined(separator: " ")] ?? [] { add(h, cs); hit = true }
                        }
                        if hit { step = L; break }
                    }
                    i += step
                }
                return keys
            }
        }
        return Array(keys.sorted { d.score(Dict.hanOf($0), Dict.codesOf($0)) > d.score(Dict.hanOf($1), Dict.codesOf($1)) }.prefix(120))
    }

    static func run(_ d: Dict, _ q0: String) -> LookupResult {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        var r = LookupResult()
        guard !q.isEmpty else { return r }
        if q.contains(where: { "*＊?？".contains($0) }) { return wildcard(d, q) }
        if q.unicodeScalars.contains(where: { ConvertEngine.isZy($0.value) || ConvertEngine.isLatinLetter($0.value) }) {
            r.taigi = taigi(d, q)
            return r
        }
        var seen = Set<String>()
        func add(_ k: String, _ list: inout [String]) { if seen.insert(k).inserted { list.append(k) } }
        // the 華語 word itself, then words written the same in 台語
        for k in d.termIndex[q] ?? [] { add(k, &r.exact) }
        for c in d.hanMap[q] ?? [] {
            let k = q + "\t" + c
            add(d.baseKeys.contains(k) ? k : (d.keyOf(Opt(han: q, codes: c.split(separator: " ").map(String.init))) ?? k), &r.exact)
        }
        // 台語 words written with it
        if q.unicodeScalars.allSatisfy({ ConvertEngine.isHan($0.value) }) {
            var c: [String] = []
            for (h, cs) in d.hanMap where h != q && h.contains(q) {
                for code in cs { let k = h + "\t" + code; if d.baseKeys.contains(k) && !seen.contains(k) { c.append(k) } }
            }
            func crank(_ k: String) -> (Int, Double) { (Dict.hanOf(k).count, -d.score(Dict.hanOf(k), Dict.codesOf(k))) }
            r.contains = Array(c.sorted { crank($0) < crank($1) }.prefix(80))
            seen.formUnion(r.contains)
        }
        // 華語 glosses that contain it
        var g: [String] = []
        for (k, arr) in d.gl where !seen.contains(k) && arr.contains(where: { $0.t != q && $0.t.contains(q) }) { g.append(k) }
        func rank(_ k: String) -> Double { d.score(Dict.hanOf(k), Dict.codesOf(k)) - 0.15 * Double(Dict.hanOf(k).count) }
        r.gloss = Array(g.sorted { rank($0) > rank($1) }.prefix(60))
        seen.formUnion(r.gloss)
        // meanings that mention it
        var m: [String] = []
        for (k, i) in d.raw.defs.m where !seen.contains(k) && d.raw.defs.t[i].contains(q) { m.append(k) }
        r.defs = Array(m.sorted { rank($0) > rank($1) }.prefix(60))
        // 各地講法
        var hits = d.raw.cmp.filter { $0.zh == q }
        if hits.count < 6 { hits += d.raw.cmp.filter { $0.zh != q && $0.zh.contains(q) }.prefix(6 - hits.count) }
        for e in hits.prefix(6) {
            var order: [String] = []
            var by: [String: [Int]] = [:]
            for row in e.rows {
                let k = row.han + "\t" + row.codes
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(row.place)
            }
            r.places.append((zh: e.zh, rows: order.map { (han: Dict.hanOf($0), codes: Dict.codesOf($0), places: by[$0]!) }))
        }
        return r
    }
}

struct LookupPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("lookupQuery") private var query = ""
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var result = LookupResult()
    @State private var task: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                TextField("華語、台語漢字、羅馬字或方音，例如：醫院、食飯、tsiah png", text: $query)
                    .font(.system(size: 18))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .listRowBackground(T.fn.opacity(0.7))
            if !query.isEmpty && result.empty {
                Text("找不到「\(query)」。").foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            if result.isPattern {
                group("台語詞「\(query)」（\(result.pattern.count == 300 ? "300+" : String(result.pattern.count))）", result.pattern)
                group("華語「\(query)」的台語講法", result.patternZh)
            } else if query.isEmpty {
                Text("可以查華語、台語漢字、皓羅／台羅／白話字（聲調可以不打，例如 tsiah png）或方音。\n往右滑一個詞加到「不熟」，往左滑收藏。\n* 代表一個以上的字，? 代表剛好一個字：\n人* → 人開頭的詞　*仔 → 仔結尾　*水* → 水在中間　?仔 → 兩個字、仔結尾")
                    .font(.footnote).foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            group("台語「\(query)」", result.taigi)
            group("台語講法", result.exact)
            group("台語詞裡有「\(query)」", result.contains)
            if !result.places.isEmpty {
                Section("各地講法") {
                    ForEach(Array(result.places.enumerated()), id: \.offset) { _, e in placesBlock(e) }
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            group("華語意思有「\(query)」", result.gloss)
            group("解釋裡有「\(query)」", result.defs)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { search() }
        .onChange(of: query) { search() }
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { Lookup.run(d, q) }.value
            guard !Task.isCancelled else { return }
            result = r
        }
    }

    @ViewBuilder private func group(_ title: String, _ keys: [String]) -> some View {
        if !keys.isEmpty {
            Section(title) {
                ForEach(keys, id: \.self) { k in
                    NavigationLink(value: DictKey(k: k)) { DictRow(dict: dict, key: k) }
                        .swipeActions(edge: .leading) {
                            if store.cardStatus(k) == 0 {
                                Button { store.toggleUnknown(k) } label: { Label("加到不熟", systemImage: "star") }
                                    .tint(T.rustEdge)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(k) } label: {
                                Label(store.isSaved(k) ? "取消收藏" : "收藏", systemImage: "bookmark")
                            }
                            .tint(T.oliveEdge)
                        }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
    }

    private func row(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(k)).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.glyph)
                Text(dict.wordText(k, rom, place)).font(T.lat(16)).foregroundStyle(T.greenInk)
                Text(dict.wordText(k, 3, place)).font(.footnote).foregroundStyle(T.purpleInk)
                if let r = dict.raw.reg[k] { RegChip(reg: r) }
            }
            if let g = dict.gl[k], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).font(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(k) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).font(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }

    private func placesBlock(_ e: (zh: String, rows: [(han: String, codes: String, places: [Int])])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.zh).font(.headline).foregroundStyle(T.pinkInk)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(T.pink))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.pinkEdge, lineWidth: 1.5))
            ForEach(Array(e.rows.enumerated()), id: \.offset) { _, row in
                let key = dict.keyOf(Opt(han: row.han, codes: row.codes.split(separator: " ").map(String.init)))
                let content = VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.han).font(.system(size: 18, weight: .semibold)).foregroundStyle(T.glyph)
                        Text(dict.codes(row.codes, rom, -1)).font(T.lat(15)).foregroundStyle(T.greenInk)
                        Text(dict.codes(row.codes, 3, row.places.first ?? -1)).font(.footnote).foregroundStyle(T.purpleInk)
                    }
                    Text(row.places.compactMap { $0 < dict.raw.places.count ? dict.raw.places[$0] : nil }.joined(separator: "、"))
                        .font(.caption).foregroundStyle(row.places.contains(place) ? T.oliveInk : T.muted)
                }
                if let key, dict.raw.defs.m[key] != nil {
                    NavigationLink(value: DictKey(k: key)) { content }
                } else {
                    content
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 收藏

struct SavedPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var shareItem: ShareItem?

    var body: some View {
        let keys = store.savedKeys
        List {
            if keys.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("還沒有收藏", systemImage: "bookmark").font(.headline).foregroundStyle(T.glyph)
                    Text("在「轉換」點一個詞，或在「華語 → 台語」打開一個詞，按「收藏」就會存在這裡。")
                        .font(.footnote).foregroundStyle(T.muted)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) { row(k) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { withAnimation { store.unsave([k]) } } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if let st = store.cardStatus(k), st != 2 {
                                    Button { store.toggleUnknown(k) } label: { Label("加到不熟", systemImage: "star") }
                                        .tint(T.rustEdge)
                                }
                            }
                    }
                } header: {
                    Text("\(keys.count) 個詞（往左滑刪除，往右滑加到「不熟」）")
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            if !keys.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { share(Data(store.savedCSV(dict).utf8), "方方-收藏.csv") } label: {
                            Label("匯出 CSV（Anki）", systemImage: "tablecells")
                        }
                        Button { share(Data(keys.map { Dict.hanOf($0) + "\t" + dict.word($0, rom, -1) }.joined(separator: "\n").utf8), "方方-收藏.txt") } label: {
                            Label("匯出文字", systemImage: "doc.plaintext")
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
    }

    private func row(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(k)).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.glyph)
                Text(dict.wordText(k, rom, place)).font(T.lat(16)).foregroundStyle(T.greenInk)
                Text(dict.wordText(k, 3, place)).font(.footnote).foregroundStyle(T.purpleInk)
                Spacer(minLength: 0)
                if store.cardStatus(k) == 2 { Image(systemName: "star.fill").font(.caption).foregroundStyle(T.rustInk) }
            }
            if let g = dict.gl[k], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).font(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(k) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).font(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }

    private func share(_ data: Data, _ name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if (try? data.write(to: url, options: .atomic)) != nil { shareItem = ShareItem(url: url) }
    }
}

// MARK: - 分類

struct CategoryPane: View {
    let dict: Dict
    @State private var filter = ""
    var body: some View {
        let names = dict.raw.cats ?? []
        let counts = dict.catCounts
        let shown = names.indices.filter { filter.isEmpty || names[$0].contains(filter) }
        List {
            Section {
                TextField("找分類，例如：食物、稱謂、時間", text: $filter).autocorrectionDisabled()
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section("\(shown.count) 個分類（教育部辭典）") {
                ForEach(shown, id: \.self) { i in
                    NavigationLink(value: CatRef(i: i)) {
                        HStack {
                            Text(names[i]).foregroundStyle(T.glyph)
                            Spacer()
                            Text("\(counts[i, default: 0])").font(.footnote).foregroundStyle(T.muted)
                        }
                    }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct CategoryWordsView: View {
    let dict: Dict
    let cat: Int
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        let keys = dict.catWords[cat, default: []].sorted { store.rankOf($0) < store.rankOf($1) }
        let newOnes = keys.filter { store.cardStatus($0) == 0 }
        List {
            Section {
                Button { withAnimation(.snappy) { store.addUnknown(keys) } } label: {
                    Label(newOnes.isEmpty ? "這個分類的新詞都在卡片裡了" : "新詞全部加到「不熟」（\(newOnes.count)）",
                          systemImage: newOnes.isEmpty ? "star.fill" : "star")
                }
                .disabled(newOnes.isEmpty)
            } footer: {
                Text("最常用的在前面。往右滑一個詞加到「不熟」，往左滑收藏。")
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section("\(keys.count) 個詞") {
                ForEach(keys, id: \.self) { k in
                    NavigationLink(value: DictKey(k: k)) { DictRow(dict: dict, key: k) }
                        .swipeActions(edge: .leading) {
                            if store.cardStatus(k) == 0 {
                                Button { store.toggleUnknown(k) } label: { Label("加到不熟", systemImage: "star") }
                                    .tint(T.rustEdge)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(k) } label: {
                                Label(store.isSaved(k) ? "取消收藏" : "收藏", systemImage: "bookmark")
                            }
                            .tint(T.oliveEdge)
                        }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(dict.raw.cats.map { cat < $0.count ? $0[cat] : "" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// one word in a list: 漢字, readings, a short meaning, and whether it's in 不熟 / 熟悉 / 收藏
struct DictRow: View {
    let dict: Dict
    let key: String
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(key)).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.glyph)
                Text(dict.wordText(key, rom, place)).font(T.lat(16)).foregroundStyle(T.greenInk)
                Text(dict.wordText(key, 3, place)).font(.footnote).foregroundStyle(T.purpleInk)
                Spacer(minLength: 0)
                if store.isSaved(key) { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(T.oliveInk) }
                switch store.cardStatus(key) {
                case 2: Image(systemName: "star.fill").font(.caption).foregroundStyle(T.rustInk)
                case 1: Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(T.greenInk)
                default: EmptyView()
                }
            }
            if let g = dict.gl[key], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).font(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(key) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).font(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }
}

// MARK: - example sentences with guessed readings marked

extension Dict {
    /// 羅馬字 of an example; readings guessed by rule (not stated by the dictionary) are blue
    func sentenceText(_ tpl: String, _ sys: Int, place: Int, han: String, ink: Color = T.greenInk) -> AttributedString {
        var out = AttributedString()
        for p in sentencePieces(tpl, sys, place: place, han: han) {
            var a = AttributedString(p.text)
            if p.guessed {
                a.swiftUI.foregroundColor = T.blueInk
            }
            out += a
        }
        return out
    }
}

/// shown under examples when some readings in them are guessed
struct GuessNote: View {
    var body: some View {
        Text("藍色 = 推測的讀音（辭典沒有寫這個地方怎麼唸這個詞，照規則推出來的）")
            .font(.caption2).foregroundStyle(T.muted)
    }
}

/// guessed parts in blue (the same blue as the 漢字 on the cards), the rest left to the view's colour
func guessColored(_ pieces: [(text: String, guessed: Bool)], ink: Color? = nil) -> AttributedString {
    var out = AttributedString()
    for p in pieces {
        var a = AttributedString(p.text)
        if p.guessed { a.swiftUI.foregroundColor = T.blueInk } else if let ink { a.swiftUI.foregroundColor = ink }
        out += a
    }
    return out
}

extension Dict {
    /// a word's reading with guessed place readings in blue
    func wordText(_ key: String, _ sys: Int, _ place: Int) -> AttributedString {
        guessColored(wordPieces(key, sys, place))
    }
}
