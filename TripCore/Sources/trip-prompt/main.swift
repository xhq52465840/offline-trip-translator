import Foundation
import TripCore

// 读 stdin JSONL，每行一个样本草稿；输出 JSONL：App 完全一致的 system / few-shot / user 提示词，
// 代码换算的金额表，填好金额的目标输出，以及 OutputValidator 的校验结论。
// 模板里的 ⟨A1⟩⟨A2⟩… 用 AmountNormalizer 对原文找到的第 1、2… 个金额的中文写法替换，保证金额与 App 换算器一致。

struct Turn: Codable { var role: String; var source: String; var zh: String?; var foreign: String? }
struct Draft: Codable {
    var id: String
    var scene: String?
    var context: [Turn]
    var source: String
    var literal: String
    var glossary: [[String]]?
    var target_template: String
    var target: String?          // P3：zh-Hans（默认）或 en
}
struct AmountOut: Codable { var original: String; var value: Int; var display: String; var display_target: String }
struct Out: Codable {
    var id: String
    var system: String
    var fewshot: [[String]]
    var user: String
    var amounts: [AmountOut]
    var target: String
    var validation: String
}

let dec = JSONDecoder()
let enc = JSONEncoder(); enc.outputFormatting = [.withoutEscapingSlashes]
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let d = try? dec.decode(Draft.self, from: Data(line.utf8)) else { continue }
    var b = PromptBuilder(); b.scene = d.scene; b.target = d.target ?? "zh-Hans"
    let ctx = d.context.map { t in
        t.role == "me" ? ContextTurn(role: .me, source: t.source, foreign: t.foreign)
                       : ContextTurn(role: .them, source: t.source, zhDisplay: t.zh)
    }
    let gl = (d.glossary ?? []).compactMap { $0.count == 2 ? GlossaryHit(source: $0[0], zh: $0[1]) : nil }
    let amounts = AmountNormalizer.findAmounts(in: d.source)
    var target = d.target_template
    var bad: String?
    for (i, a) in amounts.enumerated() { target = target.replacingOccurrences(of: "⟨A\(i + 1)⟩", with: a.display(for: b.target)) }
    if target.contains("⟨A") { bad = "template-amount-unfilled" }
    let v: String
    if let b = bad { v = "rejected:\(b)" } else {
        switch OutputValidator.validate(output: target, literal: d.literal, source: d.source, context: ctx, target: b.target) {
        case .accepted: v = "accepted"
        case .unchanged: v = "unchanged"
        case .rejected(let r): v = "rejected:\(r)"
        }
    }
    let o = Out(id: d.id, system: b.system,
                fewshot: PromptBuilder.fewShot(for: b.target).map { [$0.user, $0.assistant] },
                user: b.user(context: ctx, source: d.source, literal: d.literal, glossary: gl),
                amounts: amounts.map { AmountOut(original: $0.original, value: $0.value, display: $0.display, display_target: $0.display(for: b.target)) },
                target: target, validation: v)
    print(String(data: try! enc.encode(o), encoding: .utf8)!)
}
