import Foundation
import TripCore
import TripLLM

// Linux 冷烟测试：用真实 GGUF 跑 TripCore 提示词 + 校验 + LlamaCppEngine（同一套 C API）。
let path = CommandLine.arguments.dropFirst().first ?? "/workspace/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"

struct Case { let id: String; let ctx: [ContextTurn]; let src: String; let lit: String }
let cases: [Case] = [
    Case(id: "01", ctx: [], src: "50rb belum termasuk ongkos", lit: "5万还没有包括费用"),
    Case(id: "02", ctx: [ContextTurn(role: .them, source: "50rb belum termasuk ongkos", zhDisplay: "5万不含车费"), ContextTurn(role: .me, source: "太贵了，能不能便宜一点")], src: "yang tadi 40 saja", lit: "刚才的40就行"),
    Case(id: "06", ctx: [], src: "total 1,5jt sudah termasuk tips", lit: "总共1.5jt已经包括小费"),
    Case(id: "13", ctx: [], src: "maaf kak, udah habis", lit: "对不起姐姐，udah 没有了"),
    Case(id: "18", ctx: [ContextTurn(role: .them, source: "ke bandara 200rb", zhDisplay: "去机场20万"), ContextTurn(role: .me, source: "150行吗")], src: "175 deal ya", lit: "175成交好吗"),
    Case(id: "22", ctx: [], src: "sy otw kak, 10 mnt lg", lit: "sy otw 姐姐，10 mnt lg"),
]

func ms(_ t: TimeInterval) -> String { String(format: "%.0fms", t * 1000) }

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let engine = LlamaCppEngine()
        var t = Date()
        try await engine.load(modelURL: URL(fileURLWithPath: path))
        print("load", ms(Date().timeIntervalSince(t)))
        let u = Understander(engine: engine, timeout: 30)   // Linux CPU：放宽超时，只验证逻辑
        t = Date(); try await u.warmUp(); print("warmUp(prefix)", ms(Date().timeIntervalSince(t)))
        for c in cases {
            let msgs = u.builder.messages(context: c.ctx, source: c.src, literal: c.lit, glossary: [])
            let raw = try await engine.complete(msgs)
            let s = engine.lastStats!
            let v = OutputValidator.validate(output: raw, literal: c.lit, source: c.src, context: c.ctx)
            print("[\(c.id)] \(c.src)\n  raw: \(raw)\n  validator: \(v)\n  prompt=\(s.promptTokens) reused=\(s.reusedPrefixTokens) gen=\(s.generatedTokens) ttft=\(ms(s.timeToFirstToken)) total=\(ms(s.totalTime))")
            let o = await u.understand(context: c.ctx, source: c.src, literal: c.lit)
            print("  understander: \(o)")
        }
        // 取消：只取前 2 段就中断
        var n = 0
        for try await _ in engine.generate(u.builder.messages(context: [], source: "terima kasih banyak ya kak", literal: "非常感谢姐姐"), options: .init(maxTokens: 64, stopAtNewline: false)) {
            n += 1; if n == 2 { break }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        print("cancel: received \(n) pieces, engine stats gen=\(engine.lastStats?.generatedTokens ?? -1) (<64 表示已停止)")
        // 超时路径
        let fast = Understander(engine: engine, timeout: 0.001)
        print("timeout path:", await fast.understand(context: [], source: "selamat pagi", literal: "早上好"))
    } catch { print("ERROR", error) }
    sem.signal()
}
sem.wait()
