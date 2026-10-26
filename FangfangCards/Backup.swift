import Foundation
import UIKit

/// Automatic backup to a folder the user picks once (e.g. iCloud Drive).
/// Each device writes its own file there; other devices' files are merged in,
/// so iPhone and iPad stay in step through the same folder.
extension Store {
    private static let bookmarkKey = "backupBookmark"
    private static let prefix = "方方詞卡-"

    var syncDevices: Bool {
        get { UserDefaults.standard.object(forKey: "syncDevices") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "syncDevices") }
    }

    /// e.g. 方方詞卡-iPhone-3F2A.json
    private var ownFileName: String {
        let id = UIDevice.current.identifierForVendor?.uuidString.prefix(4) ?? "0000"
        #if targetEnvironment(macCatalyst)
        let model = "Mac"
        #else
        let model = UIDevice.current.model
        #endif
        return Self.prefix + model + "-" + id + ".json"
    }

    var backupFolderURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    func restoreBackupState() {
        backupFolderName = backupFolderURL?.lastPathComponent
        if let t = UserDefaults.standard.object(forKey: "lastBackup") as? Double {
            lastBackup = Date(timeIntervalSince1970: t)
        }
    }

    /// called with the folder chosen in 設定
    func setBackupFolder(_ url: URL) -> String {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else { return "沒辦法使用這個資料夾。" }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        backupFolderName = url.lastPathComponent
        return syncNow()
    }

    func clearBackupFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        backupFolderName = nil
    }

    /// merge other devices' files, then write ours (+ one dated copy per day)
    @discardableResult
    func syncNow() -> String {
        guard loaded else { return "" }
        guard let folder = backupFolderURL else { return "還沒選擇備份資料夾。" }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        var changed = 0

        if syncDevices {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [])) ?? []
            for u in items {
                let name = u.lastPathComponent
                if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                    // another device's file that iCloud hasn't downloaded yet: fetch it for next time
                    let real = folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                    try? fm.startDownloadingUbiquitousItem(at: real)
                    continue
                }
                guard name.hasPrefix(Self.prefix), name.hasSuffix(".json"), name != ownFileName else { continue }
                if let d = coordinatedRead(u),
                   let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   obj["app"] as? String == "fangfang-cards" {
                    changed += mergeProgress(obj)
                }
            }
            if changed > 0 { save() }
        }

        let data = backupData()
        guard coordinatedWrite(data, to: folder.appendingPathComponent(ownFileName)) else {
            return "備份失敗：沒辦法寫入「\(folder.lastPathComponent)」。請重新選擇資料夾。"
        }

        // one dated copy per day in a sub-folder, keeping the newest 14
        let old = folder.appendingPathComponent("方方詞卡舊備份", isDirectory: true)
        try? fm.createDirectory(at: old, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let base = String(ownFileName.dropLast(".json".count))
        let dated = old.appendingPathComponent(base + "-" + f.string(from: Date()) + ".json")
        _ = coordinatedWrite(data, to: dated)
        if let all = try? fm.contentsOfDirectory(atPath: old.path) {
            let mine = all.filter { $0.hasPrefix(base + "-") && $0.hasSuffix(".json") }.sorted()
            for n in mine.dropLast(14) { try? fm.removeItem(at: old.appendingPathComponent(n)) }
        }

        lastBackup = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackup")
        return changed > 0 ? "已同步，從其他裝置更新了 \(changed) 個詞。" : "已備份到「\(folder.lastPathComponent)」。"
    }

    private func coordinatedRead(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            out = try? Data(contentsOf: u)
        }
        return out
    }

    private func coordinatedWrite(_ data: Data, to url: URL) -> Bool {
        var ok = false
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            ok = (try? data.write(to: u, options: .atomic)) != nil
        }
        return ok
    }
}
