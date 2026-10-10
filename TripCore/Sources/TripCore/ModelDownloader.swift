import Foundation

/// 传输层抽象：真实实现为后台 URLSession（Apple），测试用假实现。
public protocol DownloadTransport: AnyObject {
    var onProgress: ((Int64) -> Void)? { get set }          // 累计已收字节
    var onFinished: ((URL) -> Void)? { get set }            // 临时文件位置（回调返回前必须移走）
    var onFailed: ((Data?) -> Void)? { get set }            // resume data（可能为 nil）
    func start(url: URL, resumeData: Data?, allowsCellular: Bool)
    func pause()                                            // 产生 resume data 后回调 onFailed
}

public protocol DownloadEnvironment: AnyObject {
    var network: NetworkKind { get }
    func freeBytes(at url: URL) -> Int64
}

public struct InstalledRecord: Codable, Equatable, Sendable {
    public var id: String, bytes: Int64, sha256: String, installedAt: Date
}

/// 自有模型下载（技术设计 v2 §13.3）：串联状态机、传输、校验与原子安装。
public final class ModelDownloader {
    public let entry: ModelManifestEntry
    public let directory: URL                                // Application Support/models/{id}/
    public private(set) var machine: DownloadMachine
    public var onChange: ((DownloadState) -> Void)?

    private let transport: DownloadTransport
    private let env: DownloadEnvironment
    private let hasher: (URL) throws -> String
    private var resumeData: Data?
    private let fm = FileManager.default

    public var modelURL: URL { directory.appendingPathComponent("model.gguf") }
    var recordURL: URL { directory.appendingPathComponent("installed.json") }
    var stagingURL: URL { directory.appendingPathComponent("model.gguf.part") }

    public init(entry: ModelManifestEntry, directory: URL, transport: DownloadTransport, environment: DownloadEnvironment,
                hasher: @escaping (URL) throws -> String = { try SHA256Hasher.hex(fileAt: $0) }) {
        self.entry = entry; self.directory = directory; self.transport = transport; self.env = environment; self.hasher = hasher
        self.machine = DownloadMachine(entry: entry)
        transport.onProgress = { [weak self] in self?.apply(.progress(received: $0)) }
        transport.onFailed = { [weak self] data in self?.resumeData = data; self?.apply(.interrupted(hasResumeData: data != nil)) }
        transport.onFinished = { [weak self] tmp in self?.finished(tmp) }
        if installedRecordMatches() { machine = DownloadMachine.installed(entry: entry) }
    }

    /// 启动 / 前台快速检查（不算完整哈希）：记录与清单一致且文件大小一致。
    public func installedRecordMatches() -> Bool {
        guard let d = try? Data(contentsOf: recordURL),
              let r = try? JSONDecoder.iso.decode(InstalledRecord.self, from: d),
              r.id == entry.id, r.sha256.lowercased() == entry.sha256.lowercased(),
              let size = (try? fm.attributesOfItem(atPath: modelURL.path))?[.size] as? NSNumber,
              size.int64Value == entry.bytes else { return false }
        return true
    }

    public var readiness: Readiness { machine.readiness }

    public func start() {
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        apply(.start(network: env.network, freeBytes: env.freeBytes(at: directory)))
    }
    public func confirmCellular() { apply(.confirmCellular) }
    public func pause() { transport.pause() }
    public func resume() { apply(.resume(network: env.network)) }

    /// 删除模型（例如阻断后重下或清单版本变化）。
    public func remove() {
        try? fm.removeItem(at: modelURL); try? fm.removeItem(at: recordURL); try? fm.removeItem(at: stagingURL)
        machine = DownloadMachine(entry: entry); onChange?(machine.state)
    }

    private func apply(_ e: DownloadEvent) {
        let before = machine.state
        machine.handle(e)
        let after = machine.state
        // 进入 downloading 时启动传输（新开或续传）
        if case .downloading = after {
            switch before {
            case .downloading: break
            default:
                transport.start(url: URL(string: entry.url)!, resumeData: resumeData, allowsCellular: machine.policy.cellularConfirmed)
            }
        }
        if before != after { onChange?(after) }
    }

    private func finished(_ tmp: URL) {
        try? fm.removeItem(at: stagingURL)
        do { try fm.moveItem(at: tmp, to: stagingURL) } catch { apply(.interrupted(hasResumeData: false)); return }
        resumeData = nil
        apply(.finished)
        let hash = (try? hasher(stagingURL)) ?? ""
        let sizeOK = ((try? fm.attributesOfItem(atPath: stagingURL.path))?[.size] as? NSNumber)?.int64Value == entry.bytes
        apply(.verified(sha256: sizeOK ? hash : "size-mismatch"))
        switch machine.state {
        case .installed:
            do {
                try? fm.removeItem(at: modelURL)
                try fm.moveItem(at: stagingURL, to: modelURL)       // 同卷 rename，原子
                excludeFromBackup(modelURL)
                let rec = InstalledRecord(id: entry.id, bytes: entry.bytes, sha256: entry.sha256, installedAt: Date())
                try JSONEncoder.iso.encode(rec).write(to: recordURL, options: .atomic)
            } catch {
                machine = DownloadMachine(entry: entry); onChange?(machine.state)
            }
        default:
            try? fm.removeItem(at: stagingURL)                      // 校验失败：删除半成品（重试已由状态机发起）
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var u = url
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
    }
}

extension DownloadMachine {
    static func installed(entry: ModelManifestEntry) -> DownloadMachine {
        var m = DownloadMachine(entry: entry, policy: .init())
        m.forceInstalled()
        return m
    }
}

extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }

#if canImport(Darwin)
/// 后台 URLSession 传输（仅 Apple 平台；Linux 的 FoundationNetworking 不支持后台会话）。
public final class URLSessionTransport: NSObject, DownloadTransport, URLSessionDownloadDelegate {
    public var onProgress: ((Int64) -> Void)?
    public var onFinished: ((URL) -> Void)?
    public var onFailed: ((Data?) -> Void)?
    /// AppDelegate 的 handleEventsForBackgroundURLSession 完成回调
    public var backgroundCompletion: (() -> Void)?

    private let identifier: String
    private var session: URLSession!
    private var cellularSession: URLSession!
    private var task: URLSessionDownloadTask?

    public init(identifier: String = "app.tripunderstand.model") {
        self.identifier = identifier
        super.init()
        session = URLSession(configuration: Self.config(identifier, cellular: false), delegate: self, delegateQueue: .main)
        cellularSession = URLSession(configuration: Self.config(identifier + ".cellular", cellular: true), delegate: self, delegateQueue: .main)
    }

    static func config(_ id: String, cellular: Bool) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.background(withIdentifier: id)
        c.allowsCellularAccess = cellular
        c.allowsExpensiveNetworkAccess = cellular
        c.allowsConstrainedNetworkAccess = cellular
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        return c
    }

    public func start(url: URL, resumeData: Data?, allowsCellular: Bool) {
        let s = allowsCellular ? cellularSession! : session!
        task = resumeData.map { s.downloadTask(withResumeData: $0) } ?? s.downloadTask(with: url)
        task?.resume()
    }

    public func pause() {
        task?.cancel(byProducingResumeData: { [weak self] data in DispatchQueue.main.async { self?.onFailed?(data) } })
        task = nil
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { onFailed?(nil); return }
        onFinished?(location)    // 回调内同步移走文件
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if (error as NSError).code == NSURLErrorCancelled && data == nil { return }   // pause 已经回调过
        onFailed?(data)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { self.backgroundCompletion?(); self.backgroundCompletion = nil }
    }
}

/// 真实环境：网络类型来自 NWPathMonitor（由 App 层注入），空间来自 volumeAvailableCapacityForImportantUsage。
public final class SystemDownloadEnvironment: DownloadEnvironment {
    public var network: NetworkKind
    public init(network: NetworkKind) { self.network = network }
    public func freeBytes(at url: URL) -> Int64 {
        #if os(iOS)
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
        #else
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(v?.volumeAvailableCapacity ?? 0)
        #endif
    }
}
#endif
