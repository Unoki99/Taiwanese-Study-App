import SwiftUI

/// purple 「自訂」 label: a word you added yourself, not from the MOE dictionary
struct OwnChip: View {
    var body: some View { Chip(text: "自訂", fill: T.own, edge: T.ownEdge, ink: T.ownInk) }
}

/// 詞典 → 自訂: the words you added yourself
struct OwnPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @State private var adding = false

    var body: some View {
        let keys = store.ownKeys
        List {
            Section {
                Button { adding = true } label: {
                    Label("加一個詞", systemImage: "plus.circle.fill")
                        .ffFont(.headline).foregroundStyle(T.ownInk)
                }
            } footer: {
                Text("自己加的詞不是教育部辭典的內容，在「轉換」和「詞典」都會用紫色和「自訂」標示。")
            }
            .listRowBackground(T.fn.opacity(0.7))
            if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) { row(k) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { withAnimation { store.removeOwn(k) } } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("\(keys.count) 個詞（往左滑刪除）")
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $adding) {
            AddOwnWordSheet(dict: dict).environmentObject(store)
        }
    }

    private func row(_ k: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Dict.hanOf(k)).scaledFont(20, weight: .semibold).foregroundStyle(T.ownInk)
            Text(dict.codes(Dict.codesOf(k), min(max(rom, 0), 2), -1)).latFont(16).foregroundStyle(T.greenInk)
            Text(dict.codes(Dict.codesOf(k), 3, -1)).ffFont(.footnote).foregroundStyle(T.purpleInk)
            Spacer(minLength: 0)
            OwnChip()
        }
    }
}

/// add a word: 漢字 and its reading (typed in 皓羅, 台羅, 白話字 or 方音)
struct AddOwnWordSheet: View {
    let dict: Dict
    var han0 = ""
    var reading0 = ""
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @State private var han = ""
    @State private var reading = ""
    @State private var engine: ConvertEngine?

    var body: some View {
        NavigationStack {
            Form {
                Section("漢字") {
                    TextField("例：揣頭路", text: $han)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("例：tshuē-thâu-lōo", text: $reading)
                        .latFont(17)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("讀音")
                } footer: {
                    Text("用皓羅、台羅、白話字或方音都可以。寫聲調比較準；沒寫聲調的話，請看下面的結果對不對。")
                }
                Section("結果") {
                    switch check {
                    case .ok(let codes):
                        let cs = codes.joined(separator: " ")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(han.trimmingCharacters(in: .whitespaces)).scaledFont(24, weight: .semibold).foregroundStyle(T.ownInk)
                            OwnChip()
                        }
                        Text(dict.codes(cs, 0, -1)).latFont(17).foregroundStyle(T.greenInk)
                        Text(dict.codes(cs, 1, -1) + "　" + dict.codes(cs, 2, -1)).latFont(14).foregroundStyle(T.greenInk.opacity(0.8))
                        Text(dict.codes(cs, 3, -1)).foregroundStyle(T.purpleInk)
                    case .problem(let msg):
                        Text(msg).ffFont(.footnote).foregroundStyle(T.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("加一個詞")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入") {
                        if case .ok(let codes) = check {
                            store.addOwn(han.trimmingCharacters(in: .whitespaces) + "\t" + codes.joined(separator: " "))
                            dismiss()
                        }
                    }
                    .disabled({ if case .ok = check { return false }; return true }())
                }
            }
            .onAppear {
                if han.isEmpty { han = han0 }
                if reading.isEmpty { reading = reading0 }
                if engine == nil { engine = ConvertEngine(dict: dict) }
            }
        }
    }

    private enum Check { case ok([String]), problem(String) }

    /// the reading as syllable codes, one per 漢字
    private var check: Check {
        let h = han.trimmingCharacters(in: .whitespaces)
        let chars = h.unicodeScalars.filter { ConvertEngine.isHan($0.value) }
        if h.isEmpty { return .problem("先寫漢字。") }
        if chars.count != h.unicodeScalars.count { return .problem("漢字欄只能寫漢字。") }
        if reading.trimmingCharacters(in: .whitespaces).isEmpty { return .problem("再寫讀音。") }
        guard let engine else { return .problem("") }
        var codes: [String] = []
        for it in engine.convert(reading).items {
            if it.space || it.newline { continue }
            if let raw = it.raw {
                if raw.trimmingCharacters(in: CharacterSet(charactersIn: " -‑–")).isEmpty { continue }
                return .problem("看不懂「\(raw)」這個讀音。")
            }
            guard let c = it.current.codes else { return .problem("看不懂這個讀音。") }
            codes += c
        }
        if codes.isEmpty { return .problem("看不懂這個讀音。") }
        if codes.count != chars.count { return .problem("讀音有 \(codes.count) 個音節，漢字有 \(chars.count) 個字，要一樣多。") }
        let key = h + "\t" + codes.joined(separator: " ")
        if dict.baseKeys.contains(key) || (dict.altParent[key] != nil) { return .problem("辭典裡已經有這個詞了。") }
        if store.isOwn(key) { return .problem("這個詞已經在「自訂」裡了。") }
        return .ok(codes)
    }
}
