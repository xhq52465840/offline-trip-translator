import Foundation

public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String
    public init(_ role: Role, _ content: String) { self.role = role; self.content = content }
}

public struct GenerationOptions: Sendable {
    public var maxTokens: Int
    public var stopAtNewline: Bool
    public init(maxTokens: Int = 64, stopAtNewline: Bool = true) { self.maxTokens = maxTokens; self.stopAtNewline = stopAtNewline }
}

public struct GenerationStats: Equatable, Sendable {
    public var promptTokens: Int
    public var reusedPrefixTokens: Int
    public var generatedTokens: Int
    public var timeToFirstToken: TimeInterval
    public var totalTime: TimeInterval
    public init(promptTokens: Int, reusedPrefixTokens: Int, generatedTokens: Int, timeToFirstToken: TimeInterval, totalTime: TimeInterval) {
        self.promptTokens = promptTokens; self.reusedPrefixTokens = reusedPrefixTokens; self.generatedTokens = generatedTokens
        self.timeToFirstToken = timeToFirstToken; self.totalTime = totalTime
    }
}

public enum LLMError: Error, Equatable {
    case notLoaded, loadFailed(String), contextFailed, tokenizeFailed, decodeFailed(Int32), templateFailed, promptTooLong(Int)
}

/// 端侧推理引擎（技术设计 v2 §8.4）。实现必须在内部串行化，不在主线程 decode。
public protocol LLMEngine: AnyObject, Sendable {
    var isLoaded: Bool { get }
    func load(modelURL: URL) async throws
    func unload()
    /// 前缀缓存钩子：预先计算系统提示 + 少样本部分的 KV。之后 generate 自动复用最长公共前缀。
    func warmUp(prefix messages: [ChatMessage]) async throws
    /// 流式生成。消费方取消（break / Task.cancel）即停止 decode。
    func generate(_ messages: [ChatMessage], options: GenerationOptions) -> AsyncThrowingStream<String, Error>
    var lastStats: GenerationStats? { get }
}

public extension LLMEngine {
    /// 非流式：收集全部输出。
    func complete(_ messages: [ChatMessage], options: GenerationOptions = .init()) async throws -> String {
        var out = ""
        for try await piece in generate(messages, options: options) { out += piece }
        return out
    }
}

/// 测试 / 预览用的引擎：按规则返回固定输出，可模拟延迟。
public final class MockEngine: LLMEngine, @unchecked Sendable {
    public var responder: ([ChatMessage]) -> String
    public var pieceDelayNanos: UInt64
    public private(set) var isLoaded = false
    public private(set) var warmedPrefix: [ChatMessage] = []
    public private(set) var lastStats: GenerationStats?
    public private(set) var calls = 0

    public init(pieceDelayNanos: UInt64 = 0, responder: @escaping ([ChatMessage]) -> String) {
        self.pieceDelayNanos = pieceDelayNanos; self.responder = responder
    }
    public func load(modelURL: URL) async throws { isLoaded = true }
    public func unload() { isLoaded = false }
    public func warmUp(prefix messages: [ChatMessage]) async throws { warmedPrefix = messages }

    public func generate(_ messages: [ChatMessage], options: GenerationOptions) -> AsyncThrowingStream<String, Error> {
        calls += 1
        let text = responder(messages)
        let loaded = isLoaded
        let delay = pieceDelayNanos
        return AsyncThrowingStream { cont in
            let task = Task {
                guard loaded else { cont.finish(throwing: LLMError.notLoaded); return }
                var n = 0
                for ch in text {
                    if Task.isCancelled { break }
                    if options.stopAtNewline && ch == "\n" { break }
                    if n >= options.maxTokens { break }
                    if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                    if Task.isCancelled { break }
                    cont.yield(String(ch)); n += 1
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
