import SwiftUI
import TripCore
import TripAppModel

/// 首次启动的强制准备（PRD v2 §4.3）。隐私、购买、示例演示页可以在准备期间浏览（审核风险缓解）。
struct OnboardingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("先准备好，再出发").font(.title2.bold())
                        Text("这个应用全部在手机上运行，不联网也能用。第一次需要在 Wi‑Fi 下准备好语言和理解能力，\(totalSize)，下载完成后才能开始用。")
                            .foregroundStyle(.secondary)
                        Label(state.etaText, systemImage: "house.fill")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel(state.etaText)
                    }.padding(.vertical, 4)
                }
                PrepareRowsSection()
                Section {
                    Button("开始准备") { state.prepareAll() }.font(.headline)
                }
                Section("准备期间可以先看看") {
                    NavigationLink("示例演示") { DemoView() }
                    NavigationLink("隐私说明") { PrivacyView() }
                    NavigationLink("购买 / 恢复购买") { PurchaseView() }
                }
            }
            .navigationTitle("离线准备")
            .cellularConfirm()
        }
    }

    private var totalSize: String {
        let s = PrepareRows.size(state.downloader?.entry.bytes)
        return s.isEmpty ? "需要一些空间" : "理解能力\(s)，另加系统语言包"
    }
}

struct PrepareRowsSection: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Section {
            ForEach(state.rows) { row in
                HStack {
                    Text(row.title)
                    Spacer()
                    Text(row.state).foregroundStyle(row.state == "已就绪" ? Color.green : Color.secondary).font(.subheadline)
                    if row.id == "model", case .downloading = state.downloader?.readiness {
                        Button { state.downloader?.pause() } label: { Image(systemName: "pause.circle") }.buttonStyle(.borderless)
                    } else if row.id == "model", case .paused = state.downloader?.readiness {
                        Button { state.downloader?.resume() } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if row.actionable { state.prepareAll() } }
            }
        } footer: {
            Text(state.etaText + " 准备好之后，没网也能用。")
        }
    }
}

/// 准备页（导航「准备」入口，也是阻断 sheet 的「去下载」目标）。
struct PrepareView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            PrepareRowsSection()
            Section { Button("全部准备") { state.prepareAll() } }
            Section {
                NavigationLink("隐私说明") { PrivacyView() }
                NavigationLink("购买 / 恢复购买") { PurchaseView() }
            }
        }
        .navigationTitle("离线准备")
        .cellularConfirm()
    }
}

/// 每次启动 / 回前台不完整时的阻断提示（PRD v2 §4.4）。
struct BlockingSheet: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle").font(.system(size: 48))
            Text("还没准备好，暂时不能用").font(.title3.bold())
            Text("缺少：\(state.missingText)。请连上 Wi‑Fi 下载离线语言和理解能力，完成后就能断网使用。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                state.showPrepare = true
                state.prepareAll()
            } label: { Text("去下载").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            NavigationLink("查看隐私说明") { PrivacyView() }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

struct CellularConfirm: ViewModifier {
    @EnvironmentObject var state: AppState
    func body(content: Content) -> some View {
        content.alert(PrepareRows.cellularPrompt(bytes: state.downloader?.entry.bytes ?? 0), isPresented: $state.pendingCellularConfirm) {
            Button("用流量下载") { state.confirmCellular() }
            Button("取消", role: .cancel) {}
        }
    }
}
extension View { func cellularConfirm() -> some View { modifier(CellularConfirm()) } }
