import Foundation
import AVFoundation
import SwiftUI
import CryptoKit

// 轉換 read aloud with 鬥拍字 (意傳科技, suisiann.ithuan.tw).
// The voice is 意傳科技's online service; nothing of it is included in this project.

enum TaigiSpeechInfo {
    static let credit: String? = "意傳科技《鬥拍字》台語語音合成（suisiann.ithuan.tw），連線使用，語音不包含在本 App 裡。"
}

/// Reads 台羅 text aloud: split into short pieces (鬥拍字 reads at most about 25 seconds at a time),
/// each piece fetched from 鬥拍字 and kept on the device, so the same text plays offline next time.
@MainActor
final class TaigiSpeech: ObservableObject {
    static let shared = TaigiSpeech()

    enum Phase: Equatable { case idle, loading, playing, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var text: String?
    private var player: AVAudioPlayer?
    private var token = 0

    func phase(for t: String) -> Phase { text == t ? phase : .idle }

    func toggle(_ t: String) {
        if text == t, phase == .loading || phase == .playing { stop() } else { speak(t) }
    }

    func stop() {
        token += 1
        player?.stop()
        phase = .idle
        text = nil
    }

    func speak(_ t: String) {
        let parts = TaigiSpeech.chunks(t)
        guard !parts.isEmpty else { return }
        player?.stop()
        token += 1
        let my = token
        text = t
        phase = .loading
        Task {
            do {
                var next: Task<Data, Error>? = Task { try await TaigiSpeech.audio(parts[0]) }
                for i in parts.indices {
                    guard let current = next else { break }
                    let data = try await current.value
                    // fetch the next piece while this one plays
                    next = i + 1 < parts.count ? Task { try await TaigiSpeech.audio(parts[i + 1]) } : nil
                    guard my == token else { next?.cancel(); return }
                    let p = try AVAudioPlayer(data: data)
                    p.volume = Float(UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8)
                    player = p
                    phase = .playing
                    p.play()
                    try? await Task.sleep(nanoseconds: UInt64((p.duration + 0.15) * 1_000_000_000))
                    guard my == token else { next?.cancel(); return }
                }
                if my == token { phase = .idle; text = nil }
            } catch {
                guard my == token else { return }
                phase = .failed
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if my == token { phase = .idle; text = nil }
            }
        }
    }

    // MARK: pieces

    /// sentences, and long sentences cut at commas or every 28 syllables
    nonisolated static func chunks(_ s: String) -> [String] {
        var sentences: [String] = []
        var cur = ""
        for ch in s {
            cur.append(ch)
            if "。！？!?；;\n".contains(ch) || (ch == "." ) {
                sentences.append(cur); cur = ""
            }
        }
        sentences.append(cur)
        func syllables(_ x: String) -> Int {
            x.split(whereSeparator: { " -\t\n".contains($0) }).filter { $0.contains(where: { $0.isLetter }) }.count
        }
        let limit = 28
        var out: [String] = []
        for sen in sentences {
            let t = sen.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.contains(where: { $0.isLetter }) else { continue }
            if syllables(t) <= limit { out.append(t); continue }
            // at commas
            var parts: [String] = [], p = ""
            for ch in t { p.append(ch); if "，,、：:".contains(ch) { parts.append(p); p = "" } }
            parts.append(p)
            var acc = ""
            for part in parts {
                if !acc.isEmpty, syllables(acc + part) > limit { out.append(acc); acc = "" }
                acc += part
                // a single very long part: by words
                while syllables(acc) > limit {
                    let words = acc.split(separator: " ", omittingEmptySubsequences: true)
                    var head = "", n = 0
                    var rest = words[...]
                    while let w = rest.first, n + syllables(String(w)) <= limit || head.isEmpty {
                        head += (head.isEmpty ? "" : " ") + String(w); n += syllables(String(w)); rest = rest.dropFirst()
                    }
                    out.append(head)
                    acc = rest.joined(separator: " ")
                }
            }
            if acc.contains(where: { $0.isLetter }) { out.append(acc.trimmingCharacters(in: .whitespaces)) }
        }
        return out.filter { !$0.isEmpty }
    }

    // MARK: 鬥拍字

    private nonisolated static var rootDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tts", isDirectory: true)
    }

    /// the clips are only kept for the day: each day has its own folder, and older days' folders are deleted
    /// (the first time 唸出來 is shown or used after midnight). Yesterday's clips are never played again.
    private nonisolated static var cacheDir: URL {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let d = rootDir.appendingPathComponent(today, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// delete every earlier day's clips
    nonisolated static func dropOldDays() {
        let keep = cacheDir.lastPathComponent
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: rootDir.path)) ?? [] where name != keep {
            try? fm.removeItem(at: rootDir.appendingPathComponent(name))
        }
    }

    /// one piece of 台羅 as MP3
    nonisolated static func audio(_ piece: String) async throws -> Data {
        dropOldDays()
        let name = SHA256.hash(data: Data(piece.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheDir.appendingPathComponent(name + ".mp3")
        if let d = try? Data(contentsOf: file), !d.isEmpty { return d }

        // the 台羅 goes straight to the voice, so 鬥拍字 doesn't re-read anything (the readings and the
        // dashes for tone sandhi stay exactly as the app has them); its tidying step is only a fallback
        if let d = try? await bangtsam(piece) {
            try? d.write(to: file, options: .atomic)
            return d
        }
        var kip = piece
        if let url = URL(string: "https://hokbu.ithuan.tw/tau") {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._*")
            req.httpBody = Data(("taibun=" + (piece.addingPercentEncoding(withAllowedCharacters: allowed) ?? piece)).utf8)
            if let r = try? await URLSession.shared.data(for: req),
               (r.1 as? HTTPURLResponse)?.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
               let k = obj["KIP"] as? String, !k.isEmpty {
                kip = k
            }
        }
        let data = try await bangtsam(kip)
        try? data.write(to: file, options: .atomic)
        return data
    }

    /// the voice: 台羅 in, MP3 out
    private nonisolated static func bangtsam(_ taibun: String) async throws -> Data {
        var comp = URLComponents(string: "https://hapsing.ithuan.tw/bangtsam")
        comp?.queryItems = [URLQueryItem(name: "taibun", value: taibun)]
        guard let url = comp?.url else { throw URLError(.badURL) }
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 30))
        guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 200 else { throw URLError(.badServerResponse) }
        return data
    }

    nonisolated static func clearCache() {
        try? FileManager.default.removeItem(at: rootDir)
    }
}

/// 🔊 in the 轉換 result: reads the text aloud (tap again to stop)
struct TaigiSpeakButton: View {
    let text: String
    @ObservedObject private var speech = TaigiSpeech.shared

    var body: some View {
        let ph = speech.phase(for: text)
        Button { speech.toggle(text) } label: {
            HStack(spacing: 4) {
                switch ph {
                case .loading: ProgressView().controlSize(.mini)
                case .playing: Image(systemName: "stop.fill")
                case .failed: Image(systemName: "exclamationmark.triangle.fill")
                case .idle: Image(systemName: "speaker.wave.2.fill")
                }
                Text(ph == .failed ? "連不上鬥拍字" : (ph == .playing || ph == .loading ? "停" : "唸出來"))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ph == .failed ? T.rustInk : T.purpleInk)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(ph == .failed ? T.rust : Color(hex: 0x4c3a5b)))
            .overlay(Capsule().stroke(ph == .failed ? T.rustEdge : Color(hex: 0x7b3c9b), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .task { TaigiSpeech.dropOldDays() }
        .accessibilityLabel("用鬥拍字唸出來")
    }
}
