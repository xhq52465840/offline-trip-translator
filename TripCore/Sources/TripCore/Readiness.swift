import Foundation

/// 必备项（PRD v2 §4.1）。
public enum PrepareItem: Hashable, Sendable {
    case touristSpeech                 // 中文听写
    case translation(String)           // 对方语言翻译（含双向）
    case speech(String)                // 对方语言听写
    case understander                  // 理解模型
}

public enum Readiness: Equatable, Sendable {
    case ready
    case checking
    case needsDownload(bytes: Int64?)
    case downloading(progress: Double)
    case paused(progress: Double)
    case notEnoughSpace(needed: Int64?)
    case verifyFailed
    case unavailable(String)           // 对方语言听写不可用，或某方向系统翻译不支持（由本地模型直译兜底，G1）
}

public struct PrepareStatus: Equatable, Sendable {
    public var items: [PrepareItem: Readiness]
    public init(items: [PrepareItem: Readiness]) { self.items = items }

    /// 不完整的项。对方语言听写 `unavailable` 不算缺失（PRD v2 §4.1 例外）。
    public var missing: [PrepareItem] {
        items.compactMap { item, r in
            if r == .ready { return nil }
            if case .speech = item, case .unavailable = r { return nil }
            if case .translation = item, case .unavailable = r { return nil }   // G1：系统不支持的方向用本地模型直译，不阻断
            return item
        }.sorted { "\($0)" < "\($1)" }
    }
    public var isComplete: Bool { missing.isEmpty }
    public var isDownloading: Bool {
        items.values.contains { if case .downloading = $0 { return true }; return false }
    }
}

public enum GateTrigger: Sendable { case coldLaunch, foreground, downloadFinished }

public enum DeviceTier: String, Sendable {
    case a8GB, b6GB, c4GB, unsupported

    /// 技术设计 v2 §2。`c4GBEnabled` 默认 false：4GB 机型在真机实验通过前不支持。
    public static func from(physicalMemory bytes: UInt64, c4GBEnabled: Bool = false) -> DeviceTier {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 7.5 { return .a8GB }
        if gb >= 5.5 { return .b6GB }
        if gb >= 3.5 { return c4GBEnabled ? .c4GB : .unsupported }
        return .unsupported
    }
}

public enum GateDecision: Equatable, Sendable {
    case open                          // 可用
    case block(missing: [PrepareItem]) // 阻断 sheet
    case showProgress                  // 下载中，直接显示准备页进度，不重复弹
    case onboarding                    // 首次启动引导
    case unsupportedDevice
}

/// 启动 / 回前台的阻断判定（PRD v2 §4.3、§4.4）。
public enum ReadinessGate {
    public static func decide(tier: DeviceTier, status: PrepareStatus, onboardingCompleted: Bool, trigger: GateTrigger) -> GateDecision {
        if tier == .unsupported { return .unsupportedDevice }
        if status.isComplete { return .open }
        if !onboardingCompleted { return .onboarding }
        if status.isDownloading { return .showProgress }
        return .block(missing: status.missing)
    }
}

// MARK: - 自有文件下载状态机（技术设计 v2 §13.3）

public enum NetworkKind: Sendable { case wifi, cellular, none }

public struct DownloadPolicy: Equatable, Sendable {
    public var cellularConfirmed = false
    public var spaceMargin = 1.1
    public init(cellularConfirmed: Bool = false) { self.cellularConfirmed = cellularConfirmed }
}

/// 下载镜像（技术设计 v2 §13.5）：同一文件、同一 sha256，按顺序尝试。
public struct ModelMirror: Codable, Equatable, Sendable {
    public var id: String
    public var url: String
    /// 仅作说明/统计（cn / global / placeholder）
    public var region: String?
    public init(id: String, url: String, region: String? = nil) { self.id = id; self.url = url; self.region = region }
}

public struct ModelManifestEntry: Codable, Equatable, Sendable {
    public var tier: String, id: String, url: String, bytes: Int64, sha256: String
    /// 有序镜像；缺省时只用 url（兼容旧清单）
    public var mirrors: [ModelMirror]?
    public init(tier: String, id: String, url: String, bytes: Int64, sha256: String, mirrors: [ModelMirror]? = nil) {
        self.tier = tier; self.id = id; self.url = url; self.bytes = bytes; self.sha256 = sha256; self.mirrors = mirrors
    }
    /// 实际使用的有序镜像列表（去重；空列表时退回 url）
    public var orderedMirrors: [ModelMirror] {
        var out: [ModelMirror] = []
        for m in mirrors ?? [] where !out.contains(where: { $0.url == m.url }) && URL(string: m.url) != nil { out.append(m) }
        return out.isEmpty ? [ModelMirror(id: "primary", url: url)] : out
    }
}

public enum DownloadState: Equatable, Sendable {
    case idle
    case awaitingCellularConfirmation
    case notEnoughSpace(needed: Int64)
    case downloading(received: Int64, total: Int64)
    case paused(received: Int64, total: Int64, hasResumeData: Bool)
    case verifying
    case installed
    case verifyFailed(retriesLeft: Int)
    case failed(String)
}

public enum DownloadEvent: Equatable, Sendable {
    case start(network: NetworkKind, freeBytes: Int64)
    case confirmCellular
    case progress(received: Int64)
    case interrupted(hasResumeData: Bool)
    case resume(network: NetworkKind)
    case finished
    case verified(sha256: String)
}

/// 纯函数状态机：给定状态和事件，返回新状态。I/O 由调用方（URLSession 后台任务）执行。
public struct DownloadMachine: Sendable {
    public let entry: ModelManifestEntry
    public private(set) var state: DownloadState = .idle
    public private(set) var policy: DownloadPolicy
    public let maxVerifyRetries = 1
    private var retriesUsed = 0

    public init(entry: ModelManifestEntry, policy: DownloadPolicy = .init()) { self.entry = entry; self.policy = policy }

    public var readiness: Readiness {
        switch state {
        case .idle, .awaitingCellularConfirmation, .failed: return .needsDownload(bytes: entry.bytes)
        case .notEnoughSpace(let n): return .notEnoughSpace(needed: n)
        case .downloading(let r, let t): return .downloading(progress: t > 0 ? Double(r) / Double(t) : 0)
        case .paused(let r, let t, _): return .paused(progress: t > 0 ? Double(r) / Double(t) : 0)
        case .verifying: return .downloading(progress: 1)
        case .installed: return .ready
        case .verifyFailed: return .verifyFailed
        }
    }

    private func received() -> Int64 {
        switch state {
        case .downloading(let r, _), .paused(let r, _, _): return r
        default: return 0
        }
    }

    mutating func forceInstalled() { state = .installed }

    public mutating func handle(_ e: DownloadEvent) {
        switch (state, e) {
        case (_, .start(let net, let free)):
            let needed = Int64(Double(entry.bytes - received()) * policy.spaceMargin)
            if free < needed { state = .notEnoughSpace(needed: needed - free); return }
            switch net {
            case .none: state = .failed("network")
            case .cellular where !policy.cellularConfirmed: state = .awaitingCellularConfirmation
            default: state = .downloading(received: received(), total: entry.bytes)
            }
        case (.awaitingCellularConfirmation, .confirmCellular):
            policy.cellularConfirmed = true
            state = .downloading(received: 0, total: entry.bytes)
        case (.downloading(_, let t), .progress(let r)):
            state = .downloading(received: min(r, t), total: t)
        case (.downloading(let r, let t), .interrupted(let hasResume)):
            state = .paused(received: hasResume ? r : 0, total: t, hasResumeData: hasResume)
        case (.paused(let r, let t, _), .resume(let net)):
            if net == .none { return }
            if net == .cellular && !policy.cellularConfirmed { state = .awaitingCellularConfirmation; return }
            state = .downloading(received: r, total: t)
        case (.downloading, .finished):
            state = .verifying
        case (.verifying, .verified(let hash)):
            if hash.lowercased() == entry.sha256.lowercased() {
                state = .installed
            } else if retriesUsed < maxVerifyRetries {
                retriesUsed += 1
                state = .downloading(received: 0, total: entry.bytes)   // 删除半成品后自动重下一次
            } else {
                state = .verifyFailed(retriesLeft: 0)
            }
        default:
            break
        }
    }
}
