import SwiftUI
import UniformTypeIdentifiers
import TripCore
import TripAppModel

// MARK: - 触感

enum Haptics {
    static func play(_ e: HapticEvent) {
        #if canImport(UIKit)
        switch e.kind {
        case .impactMedium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .impactLight: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}

// MARK: - 首页：一个「直接开始」大按钮 + 可选场景卡片

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var path: [Scenario?] = []
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button { state.enter(scene: nil); path.append(nil) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("开始对话").font(.title2.bold())
                                Text("贴进对方的话，或按住说").font(.subheadline).opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .accessibilityHint("进入通用对话")

                    Text("在哪儿？选一个，会多一些常用句").font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Scenario.allCases) { s in
                            Button { state.enter(scene: s); path.append(s) } label: { ScenarioCard(scene: s) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("离线行程理解")
            .navigationDestination(for: Scenario?.self) { _ in ConversationView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink("离线准备") { PrepareView() }
                        NavigationLink("汇率设置") { RateSettingView() }
                        NavigationLink("隐私") { PrivacyView() }
                        NavigationLink("购买") { PurchaseView() }
                    } label: { Image(systemName: "gearshape").accessibilityLabel("设置") }
                }
            }
        }
    }
}

struct ScenarioCard: View {
    let scene: Scenario
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: scene.symbol).font(.title).foregroundStyle(Color.accentColor)
            Text(scene.title).font(.headline).foregroundStyle(.primary)
            Text(scene.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct RateSettingView: View {
    @EnvironmentObject var state: AppState
    @State private var text = ""
    var body: some View {
        Form {
            Section {
                TextField("例如 2300", text: $text).keyboardType(.decimalPad)
                Button("保存") { if let v = Double(text), v > 0 { state.rate = ExchangeRate(idrPerCny: v, updatedNote: "手动设置") } }
            } header: { Text("1 人民币 = ? 印尼盾") } footer: {
                Text("离线使用，不会联网更新。出发前按实际汇率改一次；气泡里的人民币只是约值。")
            }
        }
        .navigationTitle("汇率")
        .onAppear { text = String(Int(state.rate.idrPerCny)) }
    }
}

// MARK: - 对话：通用多轮聊天记录

struct ConversationView: View {
    @State private var confirmClear = false
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @State private var presenting: Message?

    private var model: ConversationModel { state.conversation }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = model.bannerText {
                NavigationLink { PurchaseView() } label: {
                    Text(banner).font(.footnote).frame(maxWidth: .infinity).padding(8).background(Color.yellow.opacity(0.25))
                }
            }
            if state.faceToFace {
                TranscriptList(viewer: .partner, onPresent: { _ in }).rotationEffect(.degrees(180))
                    .background(Color(.secondarySystemBackground))
                Divider()
            }
            TranscriptList(viewer: .me, onPresent: { presenting = $0 })
            clipboardBar
            PhraseStrip(scene: model.scene ?? .chat)   // 通用对话也给几句寒暄短语，少一步
            inputBar
        }
        .navigationTitle(model.scene?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(state.gate.theirLanguages, id: \.self) { l in
                        Button(Lang.displayName(l)) { model.theirLanguage = l; state.objectWillChange.send() }
                    }
                } label: {
                    Label("对方说\(Lang.displayName(model.theirLanguage))", systemImage: "globe").labelStyle(.titleAndIcon).font(.subheadline)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation { state.faceToFace.toggle() }; Haptics.play(.sent) } label: {
                    Image(systemName: state.faceToFace ? "person.2.fill" : "person.2")
                }
                .accessibilityLabel(state.faceToFace ? "关闭面对面模式" : "面对面模式")
                Menu {
                    Menu("场景") {
                        Button("不选场景") { state.enter(scene: nil) }
                        ForEach(Scenario.allCases) { s in Button(s.title) { state.enter(scene: s) } }
                    }
                    Button("开始新对话") { state.newConversation(deletePrevious: false) }
                    Button("开始新对话并删除上一场", role: .destructive) { state.newConversation(deletePrevious: true) }
                    Button("清除本机对话", role: .destructive) { confirmClear = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("更多") }
            }
        }
        .confirmationDialog("清除本机所有对话？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除", role: .destructive) { state.clearAllConversations() }
            Button("取消", role: .cancel) {}
        } message: { Text("对话只存在这台手机上，清除后无法恢复。") }
        .alert("接着上次的对话？", isPresented: $state.askContinue) {
            Button("继续") { state.continueSession() }
            Button("新对话") { state.newConversation(deletePrevious: false); state.askContinue = false }
        }
        .alert(state.speechAlert ?? "", isPresented: Binding(get: { state.speechAlert != nil }, set: { if !$0 { state.speechAlert = nil } })) {
            Button("去准备") { state.speechAlert = nil; state.showPrepare = true }
            Button("好", role: .cancel) { state.speechAlert = nil }
        }
        .navigationDestination(isPresented: $state.showPrepare) { PrepareView() }
        .fullScreenCover(item: $presenting) { m in PresentView(text: m.foreign ?? "") }
        .disabled(state.decision != .open)
    }

    /// 回前台只看 hasStrings；读取通过 PasteButton（用户主动粘贴，不额外弹授权）。
    @ViewBuilder private var clipboardBar: some View {
        if state.clipboard.visible {
            HStack {
                Image(systemName: "doc.on.clipboard")
                Text("翻译刚复制的这句").font(.body)
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let s = strings.first else { return }
                    Task { @MainActor in
                        if let text = state.clipboard.accept(s, lastSource: model.messages.last?.source) {
                            await model.receiveTheirs(text)
                        }
                        state.objectWillChange.send()
                    }
                }
                .labelStyle(.iconOnly)
                Button { state.clipboard.dismiss(); state.objectWillChange.send() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("不用")
            }
            .padding(.horizontal).padding(.vertical, 8).background(.thinMaterial)
        }
        if let n = state.clipboard.notice {
            Text(n).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let hint = model.inputHint { Text(hint).font(.callout).foregroundStyle(.red) }
            if let f = state.talk.feedback { Text(f).font(.callout).foregroundStyle(.secondary) }
            HStack(alignment: .bottom) {
                TextField("打中文，我帮你说", text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: input) { _, v in if v.count > 500 { input = String(v.prefix(500)) } }
                Button {
                    let text = input
                    Task {
                        let r = await model.sendMine(text)
                        if r == .ok { input = ""; Haptics.play(.sent) }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        model.clearHint()
                    }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)) }
                .disabled(!model.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("发送")
            }
            // 单手操作：两颗大按钮占满底部，拇指可达
            HStack(spacing: 10) {
                TalkButton(title: state.talk.buttonTitle.them, symbol: "ear", target: .them, prominent: true,
                           locale: Lang.speechLocale(model.theirLanguage))
                TalkButton(title: state.talk.buttonTitle.me, symbol: "mic.fill", target: .me, prominent: false,
                           locale: Lang.speechLocale(Lang.tourist))
            }
            .disabled(!model.trial.allowsFull || model.isTranslating)
            .opacity(model.trial.allowsFull ? 1 : 0.4)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }
}

/// 场景快捷短语：预置双语，点一下立即进入对话，可出示/复制。
struct PhraseStrip: View {
    @EnvironmentObject var state: AppState
    let scene: Scenario
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scene.phrases) { p in
                    Button { state.conversation.sendPhrase(p); Haptics.play(.sent) } label: {
                        HStack(spacing: 4) {
                            Text(p.zh).font(.callout)
                            if p.needsNativeReview {
                                // 新短语尚未经母语者审校（docs/社区真实语料.md）；上线前审校后去掉标记
                                Text("待校对").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .accessibilityHint("发给对方：\(p.foreign(state.conversation.theirLanguage))\(p.needsNativeReview ? "（译文待母语者校对）" : "")")
                }
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
    }
}

/// 整场对话记录：viewer = .me 中文为主；.partner 对方语言为主（面对面模式上半屏，旋转 180°）。
struct TranscriptList: View {
    @EnvironmentObject var state: AppState
    let viewer: Viewer
    var onPresent: (Message) -> Void

    private var model: ConversationModel { state.conversation }

    var body: some View {
        let rows = Transcript.rows(model.messages, viewer: viewer, rate: state.rate)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if rows.isEmpty {
                        Text(viewer == .me ? "把对方的话贴进来，或按住「听对方」" : "Silakan bicara · Please speak")
                            .font(.title3).foregroundStyle(.secondary).padding(.top, 60)
                    }
                    ForEach(rows) { r in
                        let m = model.messages.first { $0.id == r.id }
                        BubbleView(row: r, message: m, viewer: viewer,
                                   onPresent: { if let m { onPresent(m) } },
                                   onRetranslate: { lang in Task { await model.retranslate(r.id, as: lang) } })
                            .id(r.id)
                    }
                }
                .padding()
            }
            .onChange(of: state.tick) { _, _ in
                if let last = rows.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}

/// 双语气泡：大字＝阅读者语言，小字＝另一种语言；金额胶囊；理解说明；时间。
struct BubbleView: View {
    let row: BubbleRow
    let message: Message?
    let viewer: Viewer
    var onPresent: () -> Void = {}
    var onRetranslate: (String) -> Void = { _ in }
    @State private var copied = false

    private var trailing: Bool { row.side == .trailing }

    var body: some View {
        HStack(alignment: .bottom) {
            if trailing { Spacer(minLength: 32) }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
                Text(row.primary)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(row.pending ? Color.secondary : Color.primary)
                    .multilineTextAlignment(trailing ? .trailing : .leading)
                    .animation(.easeInOut(duration: 0.2), value: row.primary)   // 整句替换，不逐字闪
                if let s = row.secondary, !s.isEmpty {
                    Text(s).font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(trailing ? .trailing : .leading)
                }
                if !row.chips.isEmpty {
                    FlowChips(chips: row.chips)
                }
                if let n = row.note { Text(n).font(.footnote).foregroundStyle(.tertiary) }
                if viewer == .me, let m = message { actions(m) }
                Text(row.time).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(trailing ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            if !trailing { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder private func actions(_ m: Message) -> some View {
        if m.role == .them, let lang = m.offerRetranslateAs {
            Button("这句像\(Lang.displayName(lang))，按\(Lang.displayName(lang))重译") { onRetranslate(lang) }.font(.footnote)
        }
        if m.role == .me {
            switch m.status {
            case .trialBlocked:
                NavigationLink { PurchaseView() } label: { Text("试用已用完，买断后才能发给对方").font(.footnote) }
            case .translating:
                Text("正在换成对方的话").font(.footnote).foregroundStyle(.secondary)
            case .failed:
                Text("这句还没翻译出来").font(.footnote).foregroundStyle(.secondary)
            case .ready:
                HStack(spacing: 16) {
                    Button(copied ? "已复制" : "复制") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = m.foreign
                        #endif
                        Haptics.play(.understood)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    Button("出示", action: onPresent)
                }
                .font(.callout).disabled(!m.canCopyOrPresent)
            }
        }
    }
}

struct FlowChips: View {
    let chips: [AmountChip]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(chips) { ChipView(chip: $0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(chips) { ChipView(chip: $0) } }
        }
    }
}

struct ChipView: View {
    @EnvironmentObject var state: AppState
    let chip: AmountChip
    /// 仍是内置示例汇率时，人民币换算后标「示例」，避免用户把它当真实汇率
    private var sampleRate: Bool { state.rate == ExchangeRate.default }
    var body: some View {
        HStack(spacing: 4) {
            Text(chip.rupiah).font(.callout.monospacedDigit().weight(.semibold))
            Text(chip.chinese).font(.caption)
            if let c = chip.cny {
                Text(c).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                if sampleRate { Text("示例汇率").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(chip.chinese)\(chip.cny.map { "，约人民币\($0.dropFirst(3))元" } ?? "")")
    }
}

/// 按住说话按钮：按下 0.3 秒后开始，上滑约 80 点取消，最长 30 秒（逻辑在 TripAppModel.HoldToTalk）。
struct TalkButton: View {
    @EnvironmentObject var state: AppState
    let title: String
    let symbol: String
    let target: TalkTarget
    let prominent: Bool
    let locale: String
    @State private var ticker: Task<Void, Never>?

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(prominent ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .accessibilityLabel(target == .them ? "按住听对方" : "按住说中文")
            .accessibilityAddTraits(.isButton)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if state.talk.phase == .idle {
                            guard state.speechReady(for: target) else { return }
                            state.talk.press(target, locale: locale, at: Date())
                            startTicker()
                        } else {
                            let before = state.talk.phase
                            state.talk.drag(dy: v.translation.height)
                            if case .cancelZone = state.talk.phase, before != state.talk.phase { Haptics.play(.recordCancel) }
                        }
                    }
                    .onEnded { _ in
                        ticker?.cancel(); ticker = nil
                        Task { await state.handleTalk(await state.talk.release(at: Date())) }
                    }
            )
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            var started = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let outcome = await state.talk.tick(at: Date())
                if !started, case .recording = state.talk.phase { started = true; Haptics.play(.recordStart) }
                if let outcome { await state.handleTalk(outcome); break }
            }
        }
    }
}

/// 出示页（PRD v2 §8）：黑底白字，只有一句。
struct PresentView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 96, weight: .bold))
                    .minimumScaleFactor(34.0 / 96.0)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 600)
                    .accessibilityAddTraits(.isHeader)
            }
            Button("关闭") { dismiss() }.font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .gesture(DragGesture().onEnded { if $0.translation.height > 60 { dismiss() } })
        .environment(\.colorScheme, .dark)
    }
}

#Preview("首页") {
    HomeView().environmentObject(AppState.preview())
}

#Preview("对话（MockEngine）") {
    NavigationStack { ConversationView() }.environmentObject(AppState.preview())
}

#Preview("面对面 · 深色") {
    let s = AppState.preview(); s.faceToFace = true
    return NavigationStack { ConversationView() }.environmentObject(s).preferredColorScheme(.dark)
}

#Preview("大字号") {
    NavigationStack { ConversationView() }.environmentObject(AppState.preview()).dynamicTypeSize(.accessibility2)
}
