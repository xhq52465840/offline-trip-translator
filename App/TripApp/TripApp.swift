import SwiftUI
import TripCore
import TripAppModel

@main
struct TripApp: App {
    /// 界面语言（P7）：先定下来，再建 AppState（模型层文案用 L10n）
    init() { UILanguage.apply() }
    @StateObject private var state = AppState.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task { await state.refresh(.coldLaunch) }
                .onChange(of: scenePhase) { _, phase in
                    // 每次回到前台都检查（PRD v2 §4.4），并更新剪贴板提示
                    if phase == .active { Task { await state.refresh(.foreground) } }
                    if phase == .background { state.enterBackground() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.decision {
            case .unsupportedDevice: UnsupportedView()
            case .onboarding: OnboardingView()
            default: HomeView()
            }
        }
        // 不完整时的阻断 sheet：不可下滑关闭
        .sheet(isPresented: Binding(get: { state.isBlocking }, set: { _ in })) {
            NavigationStack { BlockingSheet() }.interactiveDismissDisabled(true)
        }
        .translationPrepareHost(state: state)
    }
}

struct UnsupportedView: View {
    var body: some View {
        ContentUnavailableView("这台 iPhone 内存不足，暂不支持", systemImage: "iphone.slash",
                               description: Text("需要 6GB 或以上内存的 iPhone。"))
    }
}

/// 界面语言：跟随系统（iOS 实际选中的本地化），或 App 内覆盖（写 AppleLanguages，重开 App 完全生效）
enum UILanguage {
    static let key = "ui.language"
    static func apply() {
        L10n.uiLanguage = L10n.resolve(preferred: Bundle.main.preferredLocalizations, override: UserDefaults.standard.string(forKey: key))
    }
    /// nil = 跟随系统
    static func set(_ lang: String?) {
        let d = UserDefaults.standard
        if let lang { d.set(lang, forKey: key); d.set([lang], forKey: "AppleLanguages") }
        else { d.removeObject(forKey: key); d.removeObject(forKey: "AppleLanguages") }
        apply()
    }
    static var current: String? { UserDefaults.standard.string(forKey: key) }
}

struct UILanguageView: View {
    @State private var choice: String = UILanguage.current ?? "system"
    var body: some View {
        Form {
            Section {
                Picker("界面语言", selection: $choice) {
                    Text("跟随系统").tag("system"); Text("中文").tag("zh-Hans"); Text("English").tag("en")
                }
                .pickerStyle(.inline)
                .onChange(of: choice) { _, v in UILanguage.set(v == "system" ? nil : v) }
                .accessibilityIdentifier("uiLanguagePicker")
            } footer: { Text("重新打开 App 后完全生效。对话里双方说什么语言在对话页顶部选。") }
        }
        .navigationTitle("界面语言")
    }
}
