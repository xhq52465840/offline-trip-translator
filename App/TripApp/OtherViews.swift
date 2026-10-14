import SwiftUI
import StoreKit
import TripCore
import TripAppModel

/// 示例演示（不调用模型，审核期间也能看懂产品；PRD v2 §17 R1）。
struct DemoView: View {
    @State private var showUnderstood = false
    var body: some View {
        List {
            Section {
                Toggle("显示理解后的结果", isOn: $showUnderstood.animation())
            } footer: { Text(L10n.t("这是预先录好的示例对话，不需要下载就能看。") + "\n" + Copy.amountTrust) }
            ForEach(DemoScript.lines) { l in
                VStack(alignment: l.role == .me ? .trailing : .leading, spacing: 4) {
                    Text(l.role == .me ? l.source : (showUnderstood ? l.understood : l.literal)).font(.title3)
                    Text(l.role == .me ? l.understood : l.source).font(.subheadline).foregroundStyle(.secondary)
                    if l.role == .them && showUnderstood && l.understood != l.literal {
                        Text(L10n.f("字面：%@", l.literal)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: l.role == .me ? .trailing : .leading)
            }
        }
        .navigationTitle("示例演示")
    }
}

struct PrivacyView: View {
    @State private var metricsOn = MetricsSettings().enabled
    var body: some View {
        List {
            Section {
                Text("对话、录音、翻译、理解全部在这台手机上完成；录音不保存。")
                Text("有网也不会改成在线翻译、在线听写或在线模型。")
                Text("网络只用于下载语言包和理解能力、App Store 购买，以及可关闭的匿名计数。")
                Text("没有账号。买断状态由 App Store 恢复。")
            }
            Section {
                Toggle("匿名使用计数", isOn: $metricsOn)
                    .onChange(of: metricsOn) { _, v in MetricsSettings().enabled = v }
            } footer: { Text("只统计次数和耗时，不含任何原文、译文、录音或剪贴板内容。") }
        }
        .navigationTitle("隐私说明")
    }
}

@MainActor
final class PurchaseModel: ObservableObject {
    /// 决策 D4：单次旅行包（30 天非续期订阅）+ 终身买断（非消耗型）。价格为提案，以 App Store Connect 为准。
    static let productIDs = PurchaseProduct.allCases.map(\.rawValue)
    @Published var products: [Product] = []
    @Published var entitlement: EntitlementResolver.Result = .none
    @Published var message: String?
    var unlocked: Bool { entitlement != .none }

    func load() async {
        let ps = (try? await Product.products(for: Self.productIDs)) ?? []
        // 旅行包在前、终身在后
        products = ps.sorted { Self.productIDs.firstIndex(of: $0.id) ?? 0 < Self.productIDs.firstIndex(of: $1.id) ?? 0 }
        if products.isEmpty { message = L10n.t("价格暂时取不到") }
        await refreshEntitlement()
    }

    /// 非续期订阅系统不管到期，App 自己按购买日期 + 30 天算（EntitlementResolver，有单测）。
    func refreshEntitlement() async {
        var txns: [EntitlementResolver.Txn] = []
        for await result in Transaction.all {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID) {
                txns.append(.init(productID: t.productID, purchaseDate: t.purchaseDate, revoked: t.revocationDate != nil))
            }
        }
        entitlement = EntitlementResolver.resolve(txns, now: Date())
    }

    func buy(_ product: Product) async {
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish() }
                await refreshEntitlement()
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch { message = L10n.t("没买成，可以再试") }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { message = L10n.t("没买成，可以再试") }
        await refreshEntitlement()
    }
}

struct PurchaseView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let p = state.purchase
        List {
            Section {
                Text("没网能用")
                Text("中文、印尼语、英语任意互译，都能听、能看、能递给对方")
                Text("不自动续费")
                Text(Copy.amountTrust).font(.footnote).foregroundStyle(.secondary)
            } footer: { Text("免费试用 24 小时：从第一条翻译开始计时，期间不限条数。试用结束后只能看对方消息的字面意思。购买后仍需完成离线准备。") }
            Section {
                switch p.entitlement {
                case .lifetime: Text("已终身买断")
                case .passUntil(let d): Text(L10n.f("旅行包有效期至 %@", d.formatted(date: .abbreviated, time: .omitted)))
                case .none: EmptyView()
                }
                if p.entitlement != .lifetime {
                    ForEach(p.products, id: \.id) { prod in
                        Button {
                            Task { await p.buy(prod); sync() }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(prod.id == PurchaseProduct.tripPass.rawValue ? L10n.f("单次旅行包（30 天）%@", prod.displayPrice) : L10n.f("终身买断 %@", prod.displayPrice))
                                Text(prod.id == PurchaseProduct.tripPass.rawValue ? "一次旅行够用，到期不自动续费" : "以后每次去都能用")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if p.products.isEmpty { Text("价格暂时取不到").foregroundStyle(.secondary) }
                }
                Button("恢复购买") { Task { await p.restore(); sync() } }.accessibilityIdentifier("restorePurchases")
            }
            if let m = p.message { Text(m).foregroundStyle(.secondary) }
        }
        .navigationTitle("购买")
        .accessibilityIdentifier("purchase")
        .task { await p.load(); sync() }
    }
    private func sync() {
        state.conversation.trial.unlocked = state.purchase.unlocked
        state.objectWillChange.send()
    }
}

/// 决策 D2：下载期间唯一可用的功能——预置短语，点一下全屏出示给对方。不联网、不用模型、不计试用。
struct PhraseBookView: View {
    @EnvironmentObject var state: AppState
    @State private var lang = "id"
    @State private var showing: Phrase?
    var body: some View {
        List {
            Section {
                Picker("对方语言", selection: $lang) {
                    ForEach(Lang.all.filter { $0 != state.myLanguage }, id: \.self) { l in Text(Lang.displayName(l)).tag(l) }   // r5：英文界面不再显示「中文」
                }.pickerStyle(.segmented)
            } footer: { Text("下载完成前只能用这些预先翻好的句子。点一下，把屏幕给对方看。") }
            ForEach(PhraseBook.sections(recent: state.recentScenes)) { sec in
                Section(sec.scene.title) {
                    ForEach(sec.phrases, id: \.zh) { p in
                        Button { showing = p } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.text(state.myLanguage)).font(.body.weight(.semibold))
                                    Text(p.text(lang)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.needsNativeReview { Text("待校对").font(.caption2).foregroundStyle(.orange) }
                            }
                        }
                        .accessibilityHint("全屏出示给对方")
                        .accessibilityIdentifier("phrase_\(p.zh)")
                    }
                }
            }
        }
        .contentMargins(.bottom, 48, for: .scrollContent)   // r5：最后一行不被 Home 指示条挡住
        .navigationTitle("常用句（离线可用）")
        .accessibilityIdentifier("phraseBook")
        .onAppear { if lang == state.myLanguage { lang = state.myLanguage == "id" ? "zh-Hans" : "id" } }
        .fullScreenCover(item: $showing) { p in
            PresentView(text: PhraseBook.present(p, lang: lang, myLanguage: state.myLanguage).big, amountLine: nil)
        }
    }
}
