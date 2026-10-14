import XCTest
@testable import TripCore

final class FakeTransport: DownloadTransport {
    var onProgress: ((Int64) -> Void)?
    var onFinished: ((URL) -> Void)?
    var onFailed: ((Data?) -> Void)?
    var starts: [(url: URL, resume: Data?, cellular: Bool)] = []
    var payload: Data
    init(payload: Data) { self.payload = payload }
    func start(url: URL, resumeData: Data?, allowsCellular: Bool) { starts.append((url, resumeData, allowsCellular)) }
    func pause() { onFailed?(Data("resume-token".utf8)) }
    func deliver(_ data: Data? = nil) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID())")
        try! (data ?? payload).write(to: tmp)
        onProgress?(Int64((data ?? payload).count))
        onFinished?(tmp)
    }
}

final class FakeEnv: DownloadEnvironment {
    var network: NetworkKind = .wifi
    var free: Int64 = 1 << 40
    func freeBytes(at url: URL) -> Int64 { free }
}

final class DownloaderTests: XCTestCase {
    let payload = Data((0..<5000).map { UInt8($0 % 251) })
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID())") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func make(sha: String? = nil, transport: FakeTransport? = nil, env: FakeEnv = FakeEnv()) -> (ModelDownloader, FakeTransport, FakeEnv) {
        let t = transport ?? FakeTransport(payload: payload)
        let e = ModelManifestEntry(tier: "b6GB", id: "m1", url: "https://example.com/m.gguf", bytes: Int64(payload.count), sha256: sha ?? SHA256Hasher.hex(payload))
        return (ModelDownloader(entry: e, directory: dir, transport: t, environment: env), t, env)
    }

    func testInstallAndReopen() throws {
        let (d, t, _) = make()
        d.start()
        XCTAssertEqual(t.starts.count, 1); XCTAssertFalse(t.starts[0].cellular); XCTAssertNil(t.starts[0].resume)
        t.deliver()
        XCTAssertEqual(d.machine.state, .installed)
        XCTAssertEqual(try Data(contentsOf: d.modelURL), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.stagingURL.path))
        // 重新打开：快速检查认为已安装
        let (d2, _, _) = make()
        XCTAssertEqual(d2.readiness, .ready)
        // 文件被截断：快速检查失败 -> 需要下载（阻断）
        try Data([1, 2, 3]).write(to: d2.modelURL)
        XCTAssertFalse(make().0.installedRecordMatches())
    }

    func testCellularPolicy() {
        let env = FakeEnv(); env.network = .cellular
        let (d, t, _) = make(env: env)
        d.start()
        XCTAssertEqual(d.machine.state, .awaitingCellularConfirmation); XCTAssertTrue(t.starts.isEmpty)
        d.confirmCellular()
        XCTAssertEqual(t.starts.count, 1); XCTAssertTrue(t.starts[0].cellular)
    }

    func testPauseResumeUsesResumeData() {
        let (d, t, _) = make()
        d.start(); t.onProgress?(1200)
        d.pause()
        XCTAssertEqual(d.machine.state, .paused(received: 1200, total: 5000, hasResumeData: true))
        d.resume()
        XCTAssertEqual(t.starts.count, 2); XCTAssertEqual(t.starts[1].resume, Data("resume-token".utf8))
        t.deliver(); XCTAssertEqual(d.machine.state, .installed)
    }

    func testBadHashRetriesOnceThenFails() {
        let (d, t, _) = make(sha: String(repeating: "0", count: 64))
        d.start(); t.deliver()
        XCTAssertEqual(t.starts.count, 2, "校验失败自动重下一次")
        XCTAssertNil(t.starts[1].resume)
        t.deliver()
        XCTAssertEqual(d.machine.state, .verifyFailed(retriesLeft: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.modelURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.stagingURL.path))
    }

    func testTruncatedDownloadRejected() {
        let (d, t, _) = make()
        d.start(); t.deliver(payload.prefix(100)); t.deliver(payload.prefix(100))
        XCTAssertEqual(d.machine.state, .verifyFailed(retriesLeft: 0))
    }

    func testNoSpace() {
        let env = FakeEnv(); env.free = 10
        let (d, t, _) = make(env: env)
        d.start()
        XCTAssertEqual(d.readiness, .notEnoughSpace(needed: 5490))
        XCTAssertTrue(t.starts.isEmpty)
    }

    func testRemove() {
        let (d, t, _) = make(); d.start(); t.deliver()
        d.remove()
        XCTAssertEqual(d.readiness, .needsDownload(bytes: 5000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.modelURL.path))
    }

    func testBundledManifest() throws {
        let m = try ModelManifest.bundled()
        let e = try XCTUnwrap(m.entry(for: .b6GB))
        XCTAssertEqual(e.bytes, 986_048_640)
        XCTAssertEqual(e.sha256, "691a1b2b1e0b73e3e2156583505300697753184477176301924877f73bf05b0a")
        XCTAssertTrue(e.url.hasPrefix("https://github.com/xhq52465840/offline-trip-translator/releases/download/model-s400-v1/"))
        XCTAssertNil(m.entry(for: .c4GB), "4GB 档默认不提供模型")
        XCTAssertNotNil(m.entry(for: .a8GB))
    }
}
