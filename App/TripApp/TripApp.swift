import SwiftUI
import TripCore
import TripAppModel

@main
struct TripApp: App {
    @StateObject private var state = AppState.live()
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
            default: ConversationView()
            }
        }
        // 不完整时的阻断 sheet：不可下滑关闭
        .sheet(isPresented: Binding(get: { state.isBlocking }, set: { _ in })) {
            BlockingSheet().interactiveDismissDisabled(true)
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
