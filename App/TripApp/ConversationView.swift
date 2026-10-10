import SwiftUI
import UniformTypeIdentifiers
import TripCore
import TripAppModel

struct ConversationView: View {
    @State private var confirmClear = false
    @EnvironmentObject var state: AppState
    @State private var input = ""
    @State private var presenting: Message?

    private var model: ConversationModel { state.conversation }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner = model.bannerText {
                    NavigationLink { PurchaseView() } label: {
                        Text(banner).font(.footnote).frame(maxWidth: .infinity).padding(8).background(.yellow.opacity(0.25))
                    }
                }
                messageList
                clipboardBar
                inputBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("准备") { PrepareView() }
                }
                ToolbarItem(placement: .principal) {
                    Menu("对方说\(Lang.displayName(model.theirLanguage)) ▾") {
                        ForEach(state.gate.theirLanguages, id: \.self) { l in
                            Button(Lang.displayName(l)) { model.theirLanguage = l; state.objectWillChange.send() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("新对话") {
                        Button("开始新对话") { state.newConversation(deletePrevious: false) }
                        Button("开始新对话并删除上一场", role: .destructive) { state.newConversation(deletePrevious: true) }
                        Button("清除本机对话", role: .destructive) { confirmClear = true }
                    }
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
        }
        .disabled(state.decision != .open)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.messages.isEmpty {
                        Text("把对方的话贴进来，或按住听对方").foregroundStyle(.secondary).padding(.top, 80)
                    }
                    ForEach(model.messages) { m in
                        MessageBubble(message: m, onPresent: { presenting = m }, onRetranslate: { lang in
                            Task { await model.retranslate(m.id, as: lang) }
                        })
                        .id(m.id)
                    }
                }.padding()
            }
            .onChange(of: state.tick) { _, _ in
                if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    /// 回前台只看 hasStrings；读取通过 PasteButton（用户主动粘贴，不额外弹授权）。
    @ViewBuilder private var clipboardBar: some View {
        if state.clipboard.visible {
            HStack {
                Text("翻译刚复制的这句").font(.subheadline)
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
            }
            .padding(.horizontal).padding(.vertical, 6).background(.thinMaterial)
        }
        if let n = state.clipboard.notice {
            Text(n).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let hint = model.inputHint { Text(hint).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("用中文说你要讲的", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: input) { _, v in if v.count > 500 { input = String(v.prefix(500)) } }
                Button("发送") {
                    let text = input
                    Task {
                        let r = await model.sendMine(text)
                        if r == .ok { input = "" }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        model.clearHint()
                    }
                }
                .disabled(!model.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 12) {
                TalkButton(title: state.talk.buttonTitle.them, target: .them, prominent: true,
                           locale: Lang.speechLocale(model.theirLanguage))
                TalkButton(title: state.talk.buttonTitle.me, target: .me, prominent: false,
                           locale: Lang.speechLocale(Lang.tourist))
            }
            .disabled(!model.trial.allowsFull || model.isTranslating)
            if let f = state.talk.feedback { Text(f).font(.caption).foregroundStyle(.secondary) }
            .opacity(model.trial.allowsFull ? 1 : 0.4)
        }
        .padding()
    }
}

/// 按住说话按钮：按下 0.3 秒后开始，上滑约 80 点取消，最长 30 秒（逻辑在 TripAppModel.HoldToTalk）。
struct TalkButton: View {
    @EnvironmentObject var state: AppState
    let title: String
    let target: TalkTarget
    let prominent: Bool
    let locale: String
    @State private var ticker: Task<Void, Never>?

    var body: some View {
        Text(title)
            .font(prominent ? .headline : .body)
            .frame(maxWidth: .infinity, minHeight: prominent ? 56 : 44)
            .background(prominent ? Color.blue.opacity(0.85) : Color.gray.opacity(0.2))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(target == .them ? "按住听对方" : "按住说中文")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if state.talk.phase == .idle {
                            guard state.speechReady(for: target) else { return }
                            state.talk.press(target, locale: locale, at: Date())
                            startTicker()
                        } else {
                            state.talk.drag(dy: v.translation.height)
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
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let outcome = await state.talk.tick(at: Date()) { await state.handleTalk(outcome); break }
            }
        }
    }
}

struct MessageBubble: View {
    let message: Message
    var onPresent: () -> Void = {}
    var onRetranslate: (String) -> Void = { _ in }
    @State private var copied = false

    var body: some View {
        HStack {
            if message.role == .me { Spacer(minLength: 40) }
            VStack(alignment: message.role == .me ? .trailing : .leading, spacing: 4) {
                Text(message.mainLine)
                    .font(.title3)
                    .foregroundStyle(message.role == .them && message.literal == nil ? Color.secondary : Color.primary)
                    .animation(.easeInOut(duration: 0.2), value: message.mainLine)   // 整句替换，不逐字闪
                if message.role == .them {
                    Text(message.source).font(.subheadline).foregroundStyle(.secondary)
                    if let l = message.literalLine { Text(l).font(.caption).foregroundStyle(.tertiary) }
                    if let lang = message.offerRetranslateAs {
                        Button("这句像\(Lang.displayName(lang))，按\(Lang.displayName(lang))重译") { onRetranslate(lang) }.font(.caption)
                    }
                } else {
                    mineFooter
                }
            }
            .padding(12)
            .background(message.role == .me ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            if message.role == .them { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var mineFooter: some View {
        switch message.status {
        case .trialBlocked:
            NavigationLink { PurchaseView() } label: { Text("试用已用完，买断后才能发给对方").font(.caption) }
        case .translating:
            Text("正在换成对方的话").font(.subheadline).foregroundStyle(.secondary)
        case .failed:
            Text("这句还没翻译出来").font(.subheadline).foregroundStyle(.secondary)
        case .ready:
            Text(message.foreign ?? "").font(.body)
            if message.showBackTranslation, let b = message.backTranslation {
                Text("对方会理解成：\(b)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(copied ? "已复制" : "复制") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = message.foreign
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button("出示", action: onPresent)
            }
            .font(.subheadline).disabled(!message.canCopyOrPresent)
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

#Preview("对话（MockEngine）") {
    ConversationView().environmentObject(AppState.preview())
}

#Preview("气泡") {
    VStack {
        MessageBubble(message: .previewTheirs)
        MessageBubble(message: .previewMine)
    }.padding()
}
