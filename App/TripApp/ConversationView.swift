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

/// 汇率说明（PRD v2 §7.9）：不再手动输入；内置 ECB 汇率，有网自动更新，旧于 30 天警告。
struct RateSettingView: View {
    @EnvironmentObject var state: AppState
    @State private var refreshing = false
    var body: some View {
        let r = state.fx.rates
        Form {
            Section {
                LabeledContent("1 人民币", value: "≈ Rp " + String(Int(r.idrPerCNY.rounded())))
                LabeledContent("1 美元", value: "≈ Rp " + String(Int(r.idrPerUSD.rounded())))
                LabeledContent("日期", value: r.date)
                LabeledContent("来源", value: r.source)
                LabeledContent("换算成", value: { switch state.fx.currency { case .cny: return L10n.t("人民币"); case .usd: return L10n.t("美元"); case .idr: return L10n.t("不换算（印尼盾）") } }())
            } footer: {
                Text(state.fx.caption(now: Date()) + L10n.t("。金额由程序按原文换算，只有汇率是约值，位数不会错。有网时自动更新（只下载公开汇率，不上传任何内容）。"))
            }
            Section {
                Button(refreshing ? "更新中…" : "现在更新汇率") {
                    refreshing = true
                    Task { await state.refreshFX(force: true); refreshing = false }
                }.disabled(refreshing)
            }
        }
        .navigationTitle("汇率")
        .accessibilityIdentifier("rateSettings")
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
            statusBar
            if let banner = model.bannerText {
                NavigationLink { PurchaseView() } label: {
                    Text(banner).font(.footnote).frame(maxWidth: .infinity).padding(8).background(Color.yellow.opacity(0.25))
                }
            }
            if state.faceToFace {
                // 对方半屏（决策 D6）：对话 + 对方语言的按住说话按钮，整体旋转 180°
                VStack(spacing: 8) {
                    TranscriptList(viewer: .partner, onPresent: { _ in })
                    // P4：对方半屏自己选语言（用该语言写）
                    Menu {
                        ForEach(Lang.all.filter { $0 != state.myLanguage }, id: \.self) { l in
                            Button(LangNames.native(l)) { state.setTheirLanguage(l) }
                        }
                    } label: {
                        Label(LangNames.native(model.theirLanguage), systemImage: "globe").font(.subheadline)
                    }
                    .accessibilityIdentifier("partnerLangPicker")
                    TalkButton(title: state.talk.partnerTitle(lang: model.theirLanguage), symbol: "mic.fill", target: .them, prominent: true,
                               locale: Lang.speechLocale(model.theirLanguage))
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        .accessibilityLabel(state.talk.partnerTitle(lang: model.theirLanguage))
                }
                .rotationEffect(.degrees(180))
                .background(Color(.secondarySystemBackground))
                Divider()
            }
            TranscriptList(viewer: .me, onPresent: { presenting = $0 })
            clipboardBar
            // v4 V3：按对方上一句推荐回复；还没有对方消息时用场景短语
            PhraseStrip(scene: model.scene ?? .chat, input: $input)
            inputBar
        }
        .navigationTitle(model.scene?.title ?? L10n.t("对话"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // v4：设置入口从旧首页移到对话页左上角
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    NavigationLink("离线准备") { PrepareView() }
                    NavigationLink("汇率设置") { RateSettingView() }
                    NavigationLink("常用句") { PhraseBookView() }
                    NavigationLink("隐私") { PrivacyView() }
                    NavigationLink("界面语言") { UILanguageView() }
                    NavigationLink("购买") { PurchaseView() }
                } label: { Image(systemName: "gearshape").accessibilityLabel("设置") }
                .accessibilityIdentifier("settingsMenu")
            }
            ToolbarItem(placement: .principal) {
                // P4：「我方语言 ⇄ 对方语言」；r5：英文「I speak … / They speak …」太宽被裁切 → 只显示语言名（我方加粗），完整说法放在无障碍标签
                HStack(spacing: 6) {
                    Menu {
                        ForEach(Lang.all, id: \.self) { l in Button(LangNames.native(l)) { state.setMyLanguage(l) } }
                    } label: { Text(Lang.displayName(model.myLanguage)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7) }
                    .accessibilityLabel(L10n.f("我说%@", Lang.displayName(model.myLanguage)))
                    .accessibilityIdentifier("myLangPicker")
                    Button { state.swapLanguages() } label: { Image(systemName: "arrow.left.arrow.right") }
                        .accessibilityLabel("交换双方语言").accessibilityIdentifier("swapLangs")
                    Menu {
                        ForEach(Lang.all, id: \.self) { l in Button(LangNames.native(l)) { state.setTheirLanguage(l) } }
                    } label: { Text(Lang.displayName(model.theirLanguage)).font(.subheadline).lineLimit(1).minimumScaleFactor(0.7) }
                    .accessibilityLabel(L10n.f("对方说%@", Lang.displayName(model.theirLanguage)))
                    .accessibilityIdentifier("theirLangPicker")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation { state.faceToFace.toggle() }; Haptics.play(.sent) } label: {
                    Image(systemName: state.faceToFace ? "person.2.fill" : "person.2")
                }
                .accessibilityLabel(state.faceToFace ? "关闭面对面模式" : "面对面模式")
                .accessibilityIdentifier("faceToFaceToggle")
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
        .fullScreenCover(item: $presenting) { m in PresentView(text: m.foreign ?? "", amountLine: PresentContent.amountLine(foreign: m.foreign ?? "", source: m.source)) }
        .accessibilityIdentifier("conversationHome")
    }

    /// v4 状态条：替代阻断弹窗；非就绪时出现，点一下开始下载/去准备页。下载期间快捷句、金额、Apple 翻译照常可用。
    @ViewBuilder private var statusBar: some View {
        if let bar = state.statusBar {
            Button {
                if bar.tappable { state.prepareAll(); state.showPrepare = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: bar.isWarning ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                    Text(bar.text).font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(bar.isWarning ? Color.orange.opacity(0.25) : Color(.secondarySystemBackground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bar.text)
            .accessibilityIdentifier("statusBar")
        }
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
                TextField(model.myLanguage == "zh-Hans" ? L10n.t("打中文，我帮你说") : L10n.f("输入%@，我帮你说", Lang.displayName(model.myLanguage)), text: $input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: input) { _, v in if v.count > 500 { input = String(v.prefix(500)) } }
                    .accessibilityIdentifier("chatInput")
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
                .accessibilityIdentifier("sendButton")
            }
            // 单手操作：两颗大按钮占满底部，拇指可达
            HStack(spacing: 10) {
                TalkButton(title: state.talk.buttonTitle(myLang: model.myLanguage).them, symbol: "ear", target: .them, prominent: true,
                           locale: Lang.speechLocale(model.theirLanguage))
                TalkButton(title: state.talk.buttonTitle(myLang: model.myLanguage).me, symbol: "mic.fill", target: .me, prominent: false,
                           locale: Lang.speechLocale(model.myLanguage))
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
    @Binding var input: String
    @Environment(\.dynamicTypeSize) private var typeSize

    private var suggestion: (kind: ContextReplies.Kind, phrases: [Phrase])? { ContextReplies.suggest(messages: state.conversation.messages) }

    var body: some View {
        let s = suggestion
        let phrases = s?.phrases ?? scene.phrases
        VStack(alignment: .leading, spacing: 2) {
            if s != nil {
                Text("根据对方的话推荐").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            // 大字号（AX）时改为纵向列表，不截断
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { ForEach(phrases) { chip($0) } }.padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(phrases) { chip($0) } }.padding(.horizontal).padding(.vertical, 6)
                }
            }
        }
        .accessibilityIdentifier(s.map { "contextReplies_\($0.kind.rawValue)" } ?? "sceneReplies")
    }

    private func chip(_ p: Phrase) -> some View {
        Button { state.conversation.sendPhrase(p); Haptics.play(.sent) } label: {
            Text(p.text(state.myLanguage)).font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .contextMenu {
            Button("改一下再发") { input = p.text(state.myLanguage) }
        }
        .accessibilityHint(L10n.f("发给对方：%@", p.text(state.conversation.theirLanguage)))
        .accessibilityIdentifier("reply_\(p.zh)")
    }
}

/// 整场对话记录：viewer = .me 中文为主；.partner 对方语言为主（面对面模式上半屏，旋转 180°）。
struct TranscriptList: View {
    @EnvironmentObject var state: AppState
    let viewer: Viewer
    var onPresent: (Message) -> Void

    private var model: ConversationModel { state.conversation }

    var body: some View {
        let rows = Transcript.rows(model.messages, viewer: viewer, rate: nil, fx: viewer == .me ? state.fx : nil, lang: model.myLanguage)
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
    @EnvironmentObject var state: AppState
    @State private var copied = false
    /// 复制后提示「回 Grab 粘贴」（iOS 不能自动切回上一个 App）
    @State private var copyHint: String?

    private var trailing: Bool { row.side == .trailing }

    var body: some View {
        HStack(alignment: .bottom) {
            if trailing { Spacer(minLength: 32) }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
                // v4 V2：金额卡片永远在气泡最上方、字号最大；数字只来自程序
                if viewer == .me, let card = MoneyCard.make(chips: row.chips, source: message?.source ?? "", fromPartner: message?.role != .me) {
                    MoneyCardView(card: card)
                }
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
                    if viewer != .me { FlowChips(chips: row.chips) }
                    Text(state.fx.caption(now: Date()))
                        .font(.caption2)
                        .foregroundStyle(state.fx.isStale(now: Date()) ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("rateCaption")
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
            Button(L10n.f("这句像%@，按%@重译", Lang.displayName(lang), Lang.displayName(lang))) { onRetranslate(lang) }.font(.footnote)
        }
        if m.role == .me {
            switch m.status {
            case .trialBlocked:
                NavigationLink { PurchaseView() } label: { Text("24 小时试用已结束，购买后才能发给对方").font(.footnote) }
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
                        copyHint = CopyHint.text(scene: state.conversation.scene)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { copied = false; copyHint = nil }
                    }
                    Button("出示", action: onPresent)
                }
                .font(.callout).disabled(!m.canCopyOrPresent)
                if let h = copyHint {
                    Label(h, systemImage: "arrow.uturn.backward.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .transition(.opacity)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
    }
}

/// v4 金额卡片：原币大字 → ≈ 本币（强调色）→ 读法 + 条件。点一下全屏出示给对方。
struct MoneyCardView: View {
    let card: MoneyCard
    @State private var showing: AmountChip?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.header).font(.footnote).foregroundStyle(.secondary)
            ForEach(card.lines) { chip in
                VStack(alignment: .leading, spacing: 2) {
                    Text(chip.rupiah)
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if let c = chip.cny {
                        Text(c).font(.system(.title, design: .rounded).weight(.bold).monospacedDigit()).foregroundStyle(.orange)
                    }
                    Text(card.detail(for: chip)).font(.callout).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("amountChip")
                .onTapGesture { showing = chip }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityText)
        .accessibilityHint(L10n.t("点卡片可全屏给对方看"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showing = card.lines.first }
        .accessibilityIdentifier("moneyCard")
        .fullScreenCover(item: $showing) { c in PresentView(text: c.rupiah, amountLine: c.cny) }
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
    var body: some View {
        HStack(spacing: 4) {
            Text(chip.rupiah).font(.callout.monospacedDigit().weight(.semibold))
            Text(chip.chinese).font(.caption)
            if let c = chip.cny {
                Text(c).font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.orange.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(chip.chinese)\(chip.cny.map { "，\($0)" } ?? "")")
        .accessibilityIdentifier("amountChip")
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
            .accessibilityLabel(title)
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
    static func fontSize(for text: String) -> CGFloat {
        let longest = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(\.count).max() ?? 1
        return min(96, max(34, 330 / (CGFloat(longest) * 0.6)))
    }
    let text: String
    /// 对方熟悉的金额写法（Rp 50.000），大字单独一行，方便核对
    var amountLine: String? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ScrollView(.vertical) {
                Text(text)
                    // 按最长单词限制字号，避免 “Indonesia” 被拆成两行（r4 截图）
                    .font(.system(size: PresentView.fontSize(for: text), weight: .bold))
                    .minimumScaleFactor(34.0 / 96.0)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 600)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("presentText")
                if let a = amountLine {
                    Text(a).font(.system(size: 44, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.yellow).padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("关闭") { dismiss() }.accessibilityIdentifier("presentClose").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .gesture(DragGesture().onEnded { if $0.translation.height > 60 { dismiss() } })
        .environment(\.colorScheme, .dark)
    }
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

/// 语言选择菜单里用各语言自己的名字（P4）
enum LangNames {
    static func native(_ l: String) -> String {
        switch l { case "zh-Hans": return "中文"; case "id": return "Bahasa Indonesia"; case "en": return "English"; default: return l }
    }
}
