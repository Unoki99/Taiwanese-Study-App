import SwiftUI
import UIKit
import CoreText
import AVFoundation

@main
struct FangfangCardsApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue

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
            // the theme's colours are read while drawing: set it first, then draw everything again
            let _ = AppTheme.sync(theme)
            RootView()
                .id(theme)
                .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
                .onAppear { MacWindow.setUp() }
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
                .macTextSize()
        }
        .commands { TextSizeCommands() }
        .onChange(of: scenePhase) { _, phase in
            // pull changes from the other device when the app opens, back up when it closes
            if phase == .active { store.syncNow(); WidgetBridge.appOpened(store) }
            else if phase == .background { store.saveNow(); store.syncNow() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var router = Router.shared
    @AppStorage("place") private var place = -1
    @AppStorage("rom") private var rom = 0
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = true

    private var tabs: some View {
        TabView(selection: $router.tab) {
            NavigationStack { NewDeckView() }
                .tabItem { Label("新詞", systemImage: "rectangle.stack") }.tag(0)
            NavigationStack { UnknownView().rootPage("不熟") }
                .tabItem { Label("不熟", systemImage: "questionmark.circle") }.tag(1)
            NavigationStack { DictionaryView().rootPage("詞典") }
                .tabItem { Label("詞典", systemImage: "character.book.closed") }.tag(4)
            NavigationStack { KnownView().rootPage("熟悉") }
                .tabItem { Label("熟悉", systemImage: "checkmark.circle") }.tag(2)
            NavigationStack { ConverterView().rootPage("轉換") }
                .tabItem { Label("轉換", systemImage: "arrow.left.arrow.right") }.tag(3)
        }
    }

    var body: some View {
        Group {
            if store.loaded {
                if #available(iOS 18.0, *) {
                    // iPad and Mac: the tabs can become a sidebar
                    TabView(selection: $router.tab) {
                        // order: 新詞 不熟 詞典 熟悉 轉換 (the values stay the same for Shortcuts)
                        Tab("新詞", systemImage: "rectangle.stack", value: 0) { NavigationStack { NewDeckView() } }
                        Tab("不熟", systemImage: "questionmark.circle", value: 1) { NavigationStack { UnknownView().rootPage("不熟") } }
                        Tab("詞典", systemImage: "character.book.closed", value: 4) { NavigationStack { DictionaryView().rootPage("詞典") } }
                        Tab("熟悉", systemImage: "checkmark.circle", value: 2) { NavigationStack { KnownView().rootPage("熟悉") } }
                        Tab("轉換", systemImage: "arrow.left.arrow.right", value: 3) { NavigationStack { ConverterView().rootPage("轉換") } }
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
        // a place chosen anywhere: load the dictionary (guessed readings, example sentences)
        .onChange(of: place) {
            if place >= 0 { store.loadDict() }
            WidgetBridge.writeState(store); WidgetBridge.rebuildIfNeeded(store)
        }
        // the 分類 widgets: new spelling, the word list once loaded, local readings once the dictionary is there
        .onChange(of: rom) { WidgetBridge.writeState(store) }
        // 聲調顏色 needs the dictionary (word classes, readings in sentences)
        .onChange(of: toneSys) { if toneSys != 0 { store.loadDict() }; WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: toneMarks) { WidgetBridge.rebuildIfNeeded(store) }
        .onChange(of: store.loaded) { WidgetBridge.appOpened(store) }
        .onChange(of: store.dict != nil) { WidgetBridge.rebuildIfNeeded(store) }
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
                .macTextSize()
            }
    }
}

extension View {
    func settingsButton() -> some View {
        toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
    }

    /// a main page (tab): its name isn't shown (the tab bar shows it; it's still the back button's label).
    /// At the right, always in this order: the page's own buttons, spelling / 腔口 / 調, ⚙︎ last.
    func rootPage(_ title: String) -> some View { modifier(RootPageBar(title: title, extra: EmptyView())) }
    func rootPage<E: View>(_ title: String, @ViewBuilder extra: () -> E) -> some View {
        modifier(RootPageBar(title: title, extra: extra()))
    }
}

struct RootPageBar<Extra: View>: ViewModifier {
    let title: String
    let extra: Extra
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    extra
                    RomButton()
                    SettingsButton()
                }
            }
    }
}

/// Mac: a sensible starting and minimum window size
enum MacWindow {
    /// Mac: every window uses the chosen text size (設定 → 文字大小)
    @MainActor static func applyTextSize(_ level: Int) {
        #if targetEnvironment(macCatalyst)
        let size = UIContentSizeCategory(TextSize.levels[TextSize.clamp(level)])
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.traitOverrides.preferredContentSizeCategory = size
        }
        #endif
    }

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
    static var accent: Color { T.greenEdge }
    #else
    static var accent: Color { T.greenInk }
    #endif
}
