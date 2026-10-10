import SwiftUI
import UniformTypeIdentifiers
import TripCore
import TripAppModel

struct ConversationView: View {
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
                    Button("新对话") { model.newConversation() }
                }
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
                // 听写按钮：阶段 C 只放占位，接入 Speech 在阶段 D
                Text("按住听对方").frame(maxWidth: .infinity, minHeight: 56).background(.blue.opacity(0.85)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("按住说中文").frame(maxWidth: .infinity, minHeight: 44).background(.gray.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .opacity(model.trial.allowsFull ? 1 : 0.4)
        }
        .padding()
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
