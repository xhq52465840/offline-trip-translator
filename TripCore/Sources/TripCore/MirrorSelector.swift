import Foundation

/// 多镜像选择（技术设计 v2 §13.5）。纯逻辑，可测：
/// - 按清单顺序使用镜像；失败或过慢时切到下一个。
/// - resume data 只在**产生它的那个镜像**上续传（不同主机的 ETag/分片不保证一致，跨镜像续传不安全）；
///   切到别的镜像从 0 开始，切回原镜像时可再用它自己的 resume data。
/// - 所有镜像共用同一个 sha256；任何镜像下载完都要整文件校验，校验失败视为该镜像坏，换下一个。
/// - 一轮（每个镜像都试过）仍失败则停下交给用户重试（重试会开始新一轮）。
public struct MirrorSelector: Sendable {
    public struct Policy: Sendable, Equatable {
        /// 同一镜像连续网络失败几次后换下一个（无 resume data 时立即换）
        public var maxFailuresPerMirror: Int = 2
        /// 慢速判定：统计窗口（秒）与最低速度（字节/秒）
        public var slowWindow: TimeInterval = 20
        public var minBytesPerSecond: Double = 150_000
        /// 刚开始的若干秒不判慢（TCP 慢启动、CDN 回源）
        public var graceSeconds: TimeInterval = 10
        public init() {}
    }

    public enum Reason: String, Sendable, Equatable { case failure, slow, badHash }

    public let mirrors: [ModelMirror]
    public var policy: Policy
    public private(set) var index = 0
    public private(set) var failures: [String: Int] = [:]
    public private(set) var resumeData: [String: Data] = [:]
    /// 本轮已经放弃过的镜像
    public private(set) var exhausted: Set<String> = []
    /// 本轮因过慢被跳过的镜像（慢速切换不再切回它们；失败兜底时仍可用）
    public private(set) var slowSkipped: Set<String> = []
    public private(set) var switches: [(from: String, to: String, reason: Reason)] = []
    private var samples: [(t: Date, bytes: Int64)] = []
    private var startedAt: Date?

    public init(mirrors: [ModelMirror], policy: Policy = Policy()) {
        precondition(!mirrors.isEmpty); self.mirrors = mirrors; self.policy = policy
    }

    public var current: ModelMirror { mirrors[index] }
    public var currentResumeData: Data? { resumeData[current.id] }
    /// 本轮所有镜像都放弃了
    public var roundExhausted: Bool { exhausted.count >= mirrors.count }

    /// 开始/重新开始在当前镜像上传输
    public mutating func didStart(at t: Date) { startedAt = t; samples = [] }

    public mutating func store(resumeData d: Data?) {
        if let d { resumeData[current.id] = d } else { resumeData[current.id] = nil }
    }

    /// 网络失败。返回 true 表示应当（换了镜像或在原镜像）自动重试；false 表示本轮用尽。
    public mutating func noteFailure(resumeData d: Data?) -> Bool {
        store(resumeData: d)
        failures[current.id, default: 0] += 1
        if d == nil || failures[current.id]! >= policy.maxFailuresPerMirror {
            return advance(.failure)
        }
        return true
    }

    /// 整文件校验失败：该镜像内容坏，丢掉它的 resume data 并换下一个。
    public mutating func noteBadHash() -> Bool {
        resumeData[current.id] = nil
        return advance(.badHash)
    }

    /// 进度采样；返回 true 表示过慢且还有别的镜像可试，调用方应暂停（拿 resume data）并切换。
    public mutating func noteProgress(bytes: Int64, at t: Date) -> Bool {
        samples.append((t, bytes))
        guard let s0 = startedAt, t.timeIntervalSince(s0) >= policy.graceSeconds + policy.slowWindow else { return false }
        samples.removeAll { t.timeIntervalSince($0.t) > policy.slowWindow }
        guard let first = samples.first, t.timeIntervalSince(first.t) >= policy.slowWindow * 0.9 else { return false }
        let speed = Double(bytes - first.bytes) / max(0.001, t.timeIntervalSince(first.t))
        return speed < policy.minBytesPerSecond && nextCandidate(excludingSlow: true) != nil
    }

    /// 慢速切换（调用方已暂停并 store 了 resume data）。
    public mutating func switchForSlowness() -> Bool { advance(.slow) }

    /// 用户手动重试：开始新一轮，从第一个镜像开始（保留各镜像的 resume data）。
    public mutating func newRound() { exhausted = []; slowSkipped = []; failures = [:]; index = 0 }

    private func nextCandidate(excludingSlow: Bool = false) -> Int? {
        for k in 1..<max(2, mirrors.count + 1) {
            let j = (index + k) % mirrors.count
            let id = mirrors[j].id
            if j != index && !exhausted.contains(id) && !(excludingSlow && (slowSkipped.contains(id) || id == current.id)) { return j }
        }
        return nil
    }

    private mutating func advance(_ r: Reason) -> Bool {
        if r == .slow { slowSkipped.insert(current.id) } else { exhausted.insert(current.id) }
        guard let j = nextCandidate(excludingSlow: r == .slow) else { return false }
        switches.append((current.id, mirrors[j].id, r))
        index = j; failures[current.id] = 0
        return true
    }
}
