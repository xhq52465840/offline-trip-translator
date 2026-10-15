import SwiftUI
import TripCore
import TripAppModel

/// v4 首次打开：只做两件事 —— 选「我说 / 对方说」，点「开始用」。下载在后台进行，期间快捷句、金额换算可用。
/// 购买、隐私、汇率都在对话页的「设置」里，首屏不出现。
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var me = FirstLaunch.defaults(preferred: Locale.preferredLanguages).me
    @State private var them = FirstLaunch.defaults(preferred: Locale.preferredLanguages).them

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("你好！先选语言").font(.largeTitle.bold()).accessibilityIdentifier("onboardingTitle")
                    .accessibilityAddTraits(.isHeader)
                Text("其余都在后台准备，马上就能用常用句").foregroundStyle(.secondary)
                picker(title: "我说", selection: me, id: "onboardMe") { l in (me, them) = FirstLaunch.pick(me: l, them: them, changed: .me) }
                picker(title: "对方说", selection: them, id: "onboardThem") { l in (me, them) = FirstLaunch.pick(me: me, them: l, changed: .them) }
                VStack(alignment: .leading, spacing: 4) {
                    Label(FirstLaunch.downloadLine(bytes: state.downloader?.entry.bytes), systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.t("下载完成前：常用句和金额换算可用；翻译会提示「准备中」")).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    state.finishOnboarding(me: me, them: them)
                } label: {
                    Text("开始用").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboardStart")
            }
            .padding(24)
        }
    }

    private func picker(title: LocalizedStringKey, selection: String, id: String, onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(Lang.all, id: \.self) { l in
                Button { onPick(l) } label: {
                    HStack {
                        Text(LangNames.native(l)).font(.title3.weight(.semibold))
                        Spacer()
                        if l == selection { Image(systemName: "checkmark.circle.fill") }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .foregroundStyle(l == selection ? Color.white : Color.primary)
                    .background(l == selection ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityAddTraits(l == selection ? .isSelected : [])
                .accessibilityIdentifier("\(id)_\(l)")
            }
        }
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
                    Text(row.state).foregroundStyle(row.state == L10n.t("已就绪") ? Color.green : Color.secondary).font(.subheadline)
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
            Text(state.etaText + L10n.t(" 准备好之后，没网也能用。"))
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
                NavigationLink("购买 / 恢复购买") { PurchaseView() }.accessibilityIdentifier("purchaseLink")
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
        // r5：英文缺包说明较长，medium 高度下被截成「downloa…」→ 可滚动 + 可拉到 large，文字不截断
        ScrollView { VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle").font(.system(size: 48))
            Text("还没准备好，暂时不能用").font(.title3.bold()).accessibilityIdentifier("blockingTitle")
            Text(L10n.f("缺少：%@。请连上 Wi‑Fi 下载离线语言和理解能力，完成后就能断网使用。", state.missingText))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.showPrepare = true
                state.prepareAll()
            } label: { Text("去下载").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("blockingDownload")
            NavigationLink { PhraseBookView() } label: {
                Label("下载期间先用：常用句（出示给对方）", systemImage: "text.bubble")
            }
            .accessibilityIdentifier("blockingPhraseBook")
            NavigationLink("查看隐私说明") { PrivacyView() }
        }
        .padding(24) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
