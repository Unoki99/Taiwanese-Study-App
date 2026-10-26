import SwiftUI
import UIKit
import CoreText
import AVFoundation

@main
struct FangfangCardsApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 皓羅 font (DejaVu Sans subset) so tone marks sit right
        if let url = Bundle.main.url(forResource: "Haolo", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        // play audio even when the phone is on silent
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { MacWindow.setUp() }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            // pull changes from the other device when the app opens, back up when it closes
            if phase == .active { store.syncNow() }
            else if phase == .background { store.saveNow(); store.syncNow() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    private var tabs: some View {
        TabView {
            NavigationStack { NewDeckView().settingsButton() }
                .tabItem { Label("新詞", systemImage: "rectangle.stack") }
            NavigationStack { UnknownView().settingsButton() }
                .tabItem { Label("不熟", systemImage: "questionmark.circle") }
                .badge(store.unknownCount)
            NavigationStack { KnownView().settingsButton() }
                .tabItem { Label("熟悉", systemImage: "checkmark.circle") }
            NavigationStack { ConverterView().settingsButton() }
                .tabItem { Label("轉換", systemImage: "arrow.left.arrow.right") }
            NavigationStack { DictionaryView().settingsButton() }
                .tabItem { Label("詞典", systemImage: "character.book.closed") }
        }
    }

    var body: some View {
        Group {
            if store.loaded {
                if #available(iOS 18.0, *) {
                    // iPad and Mac: the tabs can become a sidebar
                    TabView {
                        Tab("新詞", systemImage: "rectangle.stack") { NavigationStack { NewDeckView().settingsButton() } }
                        Tab("不熟", systemImage: "questionmark.circle") { NavigationStack { UnknownView().settingsButton() } }
                            .badge(store.unknownCount)
                        Tab("熟悉", systemImage: "checkmark.circle") { NavigationStack { KnownView().settingsButton() } }
                        Tab("轉換", systemImage: "arrow.left.arrow.right") { NavigationStack { ConverterView().settingsButton() } }
                        Tab("詞典", systemImage: "character.book.closed") { NavigationStack { DictionaryView().settingsButton() } }
                    }
                    .tabViewStyle(.sidebarAdaptable)
                } else {
                    tabs
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(store.loadError ?? "載入字典…").foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .task { store.load() }
            }
        }
    }
}

/// ⚙︎ in the top bar of every tab opens 設定 (the tab bar has room for five tabs)
struct SettingsButton: View {
    @EnvironmentObject var store: Store
    @State private var show = false
    var body: some View {
        Button { show = true } label: { Image(systemName: "gearshape").foregroundStyle(T.glyph) }
            .accessibilityLabel("設定")
            .sheet(isPresented: $show) {
                NavigationStack {
                    SettingsView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { show = false } } }
                }
                .environmentObject(store)
            }
    }
}

extension View {
    func settingsButton() -> some View {
        toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
    }
}

/// Mac: a sensible starting and minimum window size
enum MacWindow {
    @MainActor static func setUp() {
        #if targetEnvironment(macCatalyst)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 620)
            scene.sizeRestrictions?.maximumSize = CGSize(width: 10000, height: 10000)
            scene.title = "方方詞卡"
        }
        #endif
    }
}

enum AppTint {
    /// light green on iPhone/iPad; on the Mac the system fills active buttons with the accent colour,
    /// so it's the darker green there (light text stays readable)
    #if targetEnvironment(macCatalyst)
    static let accent = T.greenEdge
    #else
    static let accent = T.greenInk
    #endif
}
