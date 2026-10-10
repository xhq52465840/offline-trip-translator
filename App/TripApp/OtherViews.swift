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
            } footer: { Text("这是预先录好的示例对话，不需要下载就能看。\n" + Copy.amountTrust) }
            ForEach(DemoScript.lines) { l in
                VStack(alignment: l.role == .me ? .trailing : .leading, spacing: 4) {
                    Text(l.role == .me ? l.source : (showUnderstood ? l.understood : l.literal)).font(.title3)
                    Text(l.role == .me ? l.understood : l.source).font(.subheadline).foregroundStyle(.secondary)
                    if l.role == .them && showUnderstood && l.understood != l.literal {
                        Text("字面：\(l.literal)").font(.caption).foregroundStyle(.tertiary)
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
    static let productID = "unlock.full"
    @Published var product: Product?
    @Published var unlocked = false
    @Published var message: String?

    func load() async {
        product = try? await Product.products(for: [Self.productID]).first
        if product == nil { message = "价格暂时取不到" }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var ok = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { ok = true }
        }
        unlocked = ok
    }

    func buy() async {
        guard let product else { return }
        do {
            switch try await product.purchase() {
            case .success(let v):
                if case .verified(let t) = v { await t.finish() }
                await refreshEntitlement()
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch { message = "没买成，可以再试" }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { message = "没买成，可以再试" }
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
                Text("印尼语和英语都能听、能看、能递给对方")
                Text("以后不加订阅")
                Text(Copy.amountTrust).font(.footnote).foregroundStyle(.secondary)
            } footer: { Text("可免费完整使用 30 条消息，之后只能看对方消息的字面意思。购买后仍需完成离线准备。") }
            Section {
                if p.unlocked {
                    Text("已买断")
                } else {
                    Button(p.product.map { "一次买断 \($0.displayPrice)" } ?? "价格暂时取不到") { Task { await p.buy(); sync() } }
                        .disabled(p.product == nil)
                }
                Button("恢复购买") { Task { await p.restore(); sync() } }
            }
            if let m = p.message { Text(m).foregroundStyle(.secondary) }
        }
        .navigationTitle("一次买断")
        .task { await p.load(); sync() }
    }
    private func sync() {
        state.conversation.trial.unlocked = state.purchase.unlocked
        state.objectWillChange.send()
    }
}
