import Foundation
import AVFoundation
import SwiftUI

/// Plays MOE recordings from the 方方 website; every clip played once is kept for offline use.
@MainActor
final class Player: ObservableObject {
    static let shared = Player()

    @Published private(set) var playing: String?
    @Published private(set) var failed: String?
    private var player: AVAudioPlayer?
    private var token = 0

    private var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func play(_ path: String) {
        player?.stop()
        token += 1
        let my = token
        playing = path
        failed = nil
        Task {
            do {
                let data = try await self.load(path)
                guard my == self.token else { return }
                let p = try AVAudioPlayer(data: data)
                let v = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8
                p.volume = Float(v)
                self.player = p
                p.play()
                let length = p.duration
                try? await Task.sleep(nanoseconds: UInt64((length + 0.1) * 1_000_000_000))
                if my == self.token { self.playing = nil }
            } catch {
                guard my == self.token else { return }
                self.playing = nil
                self.failed = path
            }
        }
    }

    private func load(_ path: String) async throws -> Data {
        let file = cacheDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: file), !d.isEmpty { return d }
        let base = UserDefaults.standard.string(forKey: "audioBase") ?? Audio.defaultBase
        let b = base.hasSuffix("/") ? base : base + "/"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: b + encoded) else { throw URLError(.badURL) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw URLError(.fileDoesNotExist) }
        try? data.write(to: file, options: .atomic)
        return data
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
    }
}

/// Round ▶ button in the 方方 style; turns red briefly if the recording can't be found.
struct PlayButton: View {
    let path: String
    var size: CGFloat = 34
    /// on a swipe card: frosted instead of Liquid Glass, which would stretch while the card is dragged
    var onCard = false
    @ObservedObject private var player = Player.shared
    @AppStorage("glass") private var glassOn = true

    var body: some View {
        let on = player.playing == path
        let bad = player.failed == path
        let icon = Image(systemName: "play.fill")
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(T.glyph)
            .frame(width: size, height: size)
        Button {
            player.play(path)
        } label: {
            if onCard && glassOn {
                icon
                    .background(Circle().fill(bad ? T.rustEdge.opacity(0.8) : (on ? T.greenEdge.opacity(0.9) : T.greenEdge.opacity(0.35))))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08), T.greenEdge.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5))
            } else {
                icon.glassSurface(Circle(),
                              tint: bad ? T.rustEdge.opacity(0.8) : (on ? T.greenEdge.opacity(0.9) : T.greenEdge.opacity(0.4)),
                              interactive: true,
                              fallback: bad ? T.rust : (on ? T.greenEdge : T.green.opacity(0.6)),
                              edge: bad ? T.rustEdge : T.greenEdge)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放")
    }
}
