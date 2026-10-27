import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("hideMeaning") private var hideMeaning = false
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("volume") private var volume = 0.8
    @AppStorage("goal") private var goal = 3
    @AppStorage("sessionSize") private var sessionSize = 10
    @AppStorage("audioBase") private var audioBase = Audio.defaultBase
    @AppStorage("glass") private var glassOn = true
    @AppStorage("place") private var place = -1
    @AppStorage("syncDevices") private var syncDevices = true
    @State private var pickFolder = false

    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("顯示") {
                Picker("羅馬字", selection: $rom) {
                    ForEach(0..<3, id: \.self) { Text(ROM_NAMES[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("腔口", selection: $place) {
                    Text("通行").tag(-1)
                    ForEach(Array(store.places.enumerated()), id: \.offset) { i, p in Text(p).tag(i) }
                }
                .onChange(of: place) { if place >= 0 { store.loadDict() } }
                Toggle("卡片先隱藏意思（點一下才顯示）", isOn: $hideMeaning)
                Toggle("Liquid Glass 效果", isOn: $glassOn)
            }
            Section("發音") {
                Toggle("新卡片自動播放發音", isOn: $autoPlay)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(T.muted)
                    Slider(value: $volume, in: 0...1, step: 0.05)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(T.muted)
                }
                TextField("音檔來源", text: $audioBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote)
                Button("清除已下載的音檔") { Player.shared.clearCache(); message = "已清除。" }
            }
            Section("練習") {
                Stepper("連續答對 \(goal) 次算學會", value: $goal, in: 1...6)
                Stepper("每次練習 \(sessionSize) 個詞", value: $sessionSize, in: 5...40, step: 5)
            }
            Section {
                if let name = store.backupFolderName {
                    LabeledContent("資料夾", value: name)
                    if let d = store.lastBackup {
                        LabeledContent("上次備份", value: d.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle("跟其他裝置同步", isOn: $syncDevices)
                    Button("立即備份") { message = store.syncNow() }
                    Button("換資料夾") { pickFolder = true; importing = true }
                    Button("停止自動備份", role: .destructive) { store.clearBackupFolder() }
                } else {
                    Button("選擇備份資料夾…") { pickFolder = true; importing = true }
                }
            } header: {
                Text("自動備份")
            } footer: {
                Text("選一個資料夾（建議 iCloud Drive），每次打開和離開 App 都會自動備份。iPhone 和 iPad 選同一個資料夾，進度就會互相同步。每天另外存一份到「方方詞卡舊備份」，保留 14 天。")
            }
            Section {
                Button("匯出「不熟」CSV") { share(store.csv(store.unknownCards), "方方-不熟.csv") }
                Button("匯出「熟悉」CSV") { share(store.csv(store.knownCards), "方方-熟悉.csv") }
                Button("備份檔分享／另存") { shareData(store.backupData(), "方方詞卡備份.json") }
                Button("匯入備份／方方收藏") { pickFolder = false; importing = true }
            } header: {
                Text("匯出與備份")
            } footer: {
                Text("CSV 跟方方網站的收藏格式一樣（分號分隔，九欄）。用備份可以把進度搬到另一台裝置。匯入方方網站或 Safari 擴充功能的備份，收藏的詞會加到「不熟」。")
            }
            Section {
                Button("全部重來", role: .destructive) { confirmReset = true }
            }
            Section("資料來源") {
                credit("詞條、讀音、釋義、例句、音檔、近反義詞、異用字、腔口差異、各地講法、分類、華語對照詞", "教育部《臺灣台語常用詞辭典》（創用CC 姓名標示-禁止改作 3.0 臺灣）。釋義、例句原文照錄，音檔未經修改；讀音依規則由台羅轉成皓羅、方音、白話字。")
                credit("推算的內容", "辭典沒寫的腔口讀音和例句的腔口讀音是本 App 依規則推算的，不是教育部的資料，用紅色和「推測」標示。")
                credit("音節編碼", "YuRen-tw《rime-taigi-tps》的拼音系統（經作者同意使用）")
                credit("皓羅拼寫系統", "Unoki99")
                credit("自補詞條", "Unoki99 自行補充，非教育部辭典內容")
                credit("皓羅字型", "DejaVu Sans（自由授權字型）")
                credit("方音", "臺灣方音符號")
                credit("詞頻", "依教育部辭典例句出現次數排序，Rime《八股文》（LGPL-3.0）輔助")
                Text("本 App 與教育部無關，不是官方產品。").font(.footnote).foregroundStyle(T.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("設定")
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: pickFolder ? [UTType.folder] : [UTType.json]) { result in
            guard case .success(let url) = result else { return }
            if pickFolder {
                message = store.setBackupFolder(url)
                return
            }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { message = store.importBackup(d) } else { message = "讀不到這個檔案。" }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        }
        .confirmationDialog("所有的「熟悉」和「不熟」都會清掉，從頭開始。", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("全部重來", role: .destructive) { store.resetAll() }
        }
    }

    private func credit(_ what: String, _ who: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(what).font(.caption).foregroundStyle(T.muted)
            Text(who).font(.footnote)
        }
    }

    private func share(_ text: String, _ name: String) {
        shareData(Data(text.utf8), name)
    }

    private func shareData(_ data: Data, _ name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            message = "匯出失敗。"
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
