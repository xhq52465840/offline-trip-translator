import Foundation
import TripCore
#if canImport(llama)
import llama
#elseif canImport(CLlama)
import CLlama
#endif

#if canImport(llama) || canImport(CLlama)

/// llama.cpp 引擎。C API 按 llama.cpp b11541 的 include/llama.h 核对。
/// 所有 C 调用都在私有串行队列上执行；generate 支持取消；自动复用与上次 KV 的最长公共前缀。
public final class LlamaCppEngine: LLMEngine, @unchecked Sendable {
    public struct Config: Sendable {
        public var nCtx: UInt32 = 2048
        public var nBatch: UInt32 = 512
        public var nThreads: Int32 = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1)))
        public var gpuLayers: Int32 = 99      // Apple 上走 Metal；Linux CPU 构建忽略
        public init() {}
    }

    private let queue = DispatchQueue(label: "app.tripunderstand.llama")
    private let config: Config
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var cached: [llama_token] = []        // 当前 KV 中 seq 0 的 token
    private var _stats: GenerationStats?
    private static let backendOnce: Void = { llama_backend_init() }()

    /// 不在 init 里初始化后端：llama_backend_init 会编译 Metal 着色器，放主线程会白屏约 8 秒（Mac run r1）。
    public init(config: Config = .init()) { self.config = config }
    deinit { freeAll() }

    public var isLoaded: Bool { queue.sync { ctx != nil } }
    public var lastStats: GenerationStats? { queue.sync { _stats } }

    public func load(modelURL: URL) async throws {
        try await run {
            _ = Self.backendOnce          // 首次加载时在后台队列初始化
            self.freeAll()
            var mp = llama_model_default_params()
            mp.n_gpu_layers = self.config.gpuLayers
            guard let m = llama_model_load_from_file(modelURL.path, mp) else { throw LLMError.loadFailed(modelURL.lastPathComponent) }
            var cp = llama_context_default_params()
            cp.n_ctx = self.config.nCtx
            cp.n_batch = self.config.nBatch
            cp.n_ubatch = self.config.nBatch
            cp.n_threads = self.config.nThreads
            cp.n_threads_batch = self.config.nThreads
            guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw LLMError.contextFailed }
            self.model = m; self.ctx = c; self.vocab = llama_model_get_vocab(m); self.cached = []
        }
    }

    public func unload() { queue.sync { freeAll() } }

    public func warmUp(prefix messages: [ChatMessage]) async throws {
        try await run {
            let text = try self.applyTemplate(messages, addAssistant: false)
            let toks = try self.tokenize(text, addSpecial: true)
            _ = try self.prefill(toks)
        }
    }

    public func generate(_ messages: [ChatMessage], options: GenerationOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let cancelled = CancelFlag()
            cont.onTermination = { _ in cancelled.set() }
            queue.async {
                do {
                    try self.generateSync(messages, options: options, cancelled: cancelled) { cont.yield($0) }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
        }
    }

    // MARK: - 以下只在 queue 上执行

    private func generateSync(_ messages: [ChatMessage], options: GenerationOptions, cancelled: CancelFlag, emit: (String) -> Void) throws {
        guard let ctx, let vocab else { throw LLMError.notLoaded }
        let t0 = Date()
        let text = try applyTemplate(messages, addAssistant: true)
        let toks = try tokenize(text, addSpecial: true)
        if toks.count + options.maxTokens > Int(config.nCtx) { throw LLMError.promptTooLong(toks.count) }
        let reused = try prefill(toks)

        let sparams = llama_sampler_chain_default_params()
        guard let smpl = llama_sampler_chain_init(sparams) else { throw LLMError.contextFailed }
        defer { llama_sampler_free(smpl) }
        llama_sampler_chain_add(smpl, llama_sampler_init_greedy())   // 温度 0

        var utf8 = UTF8Accumulator()
        var produced = 0
        var firstAt: Date?
        var stop = false
        while produced < options.maxTokens && !cancelled.isSet && !stop {
            let tok = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, tok) { break }
            produced += 1
            if firstAt == nil { firstAt = Date() }
            var piece = utf8.append(tokenBytes(tok))
            if options.stopAtNewline, let nl = piece.firstIndex(of: "\n") {
                piece = String(piece[..<nl]); stop = true
            }
            if !piece.isEmpty { emit(piece) }
            if stop { break }
            var t = tok
            let rc = llama_decode(ctx, llama_batch_get_one(&t, 1))
            if rc != 0 { throw LLMError.decodeFailed(rc) }
            cached.append(tok)
        }
        _stats = GenerationStats(promptTokens: toks.count, reusedPrefixTokens: reused, generatedTokens: produced,
                                 timeToFirstToken: (firstAt ?? Date()).timeIntervalSince(t0), totalTime: Date().timeIntervalSince(t0))
    }

    /// 让 KV 中 seq 0 恰好等于 toks（复用最长公共前缀），并保证最后一个 token 的 logits 可用。返回复用的 token 数。
    private func prefill(_ toks: [llama_token]) throws -> Int {
        guard let ctx else { throw LLMError.notLoaded }
        var common = 0
        while common < min(cached.count, toks.count) && cached[common] == toks[common] { common += 1 }
        if common == toks.count { common -= 1 }      // 至少重算最后一个 token 以得到 logits
        common = max(0, common)
        let mem = llama_get_memory(ctx)
        if !llama_memory_seq_rm(mem, 0, Int32(common), -1) {
            llama_memory_clear(mem, true); common = 0
        }
        cached = Array(toks[..<common])
        var i = common
        while i < toks.count {
            let n = min(Int(config.nBatch), toks.count - i)
            var chunk = Array(toks[i..<(i + n)])
            let rc = chunk.withUnsafeMutableBufferPointer { llama_decode(ctx, llama_batch_get_one($0.baseAddress, Int32(n))) }
            if rc != 0 { throw LLMError.decodeFailed(rc) }
            cached.append(contentsOf: chunk); i += n
        }
        return common
    }

    private func applyTemplate(_ messages: [ChatMessage], addAssistant: Bool) throws -> String {
        guard let model else { throw LLMError.notLoaded }
        let tmpl = llama_model_chat_template(model, nil)
        // 保持 C 字符串在调用期间有效
        let roles = messages.map { strdup($0.role.rawValue) }
        let contents = messages.map { strdup($0.content) }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        var chat = (0..<messages.count).map { llama_chat_message(role: roles[$0], content: contents[$0]) }
        var cap = Int32(max(1024, messages.reduce(0) { $0 + $1.content.utf8.count } * 2))
        for _ in 0..<2 {
            var buf = [CChar](repeating: 0, count: Int(cap))
            let n = llama_chat_apply_template(tmpl, &chat, chat.count, addAssistant, &buf, cap)
            if n < 0 { throw LLMError.templateFailed }
            if n <= cap { return String(decoding: buf[..<Int(n)].map { UInt8(bitPattern: $0) }, as: UTF8.self) }
            cap = n
        }
        throw LLMError.templateFailed
    }

    private func tokenize(_ text: String, addSpecial: Bool) throws -> [llama_token] {
        guard let vocab else { throw LLMError.notLoaded }
        let len = Int32(text.utf8.count)
        var toks = [llama_token](repeating: 0, count: Int(len) + 8)
        var n = llama_tokenize(vocab, text, len, &toks, Int32(toks.count), addSpecial, true)
        if n < 0 {
            toks = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, len, &toks, Int32(toks.count), addSpecial, true)
            if n < 0 { throw LLMError.tokenizeFailed }
        }
        return Array(toks[..<Int(n)])
    }

    private func tokenBytes(_ tok: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        var buf = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
        }
        return n > 0 ? buf[..<Int(n)].map { UInt8(bitPattern: $0) } : []
    }

    private func freeAll() {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        ctx = nil; model = nil; vocab = nil; cached = []
    }

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body() }) }
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return v }
}

#endif

