import XCTest
@testable import TripCore

final class ReadinessTests: XCTestCase {
    func full(_ over: [PrepareItem: Readiness] = [:]) -> PrepareStatus {
        var items: [PrepareItem: Readiness] = [.touristSpeech: .ready, .translation("id"): .ready, .translation("en"): .ready,
                                               .speech("id"): .ready, .speech("en"): .ready, .understander: .ready]
        for (k, v) in over { items[k] = v }
        return PrepareStatus(items: items)
    }

    func testGate() {
        XCTAssertEqual(ReadinessGate.decide(tier: .b6GB, status: full(), onboardingCompleted: true, trigger: .foreground), .open)
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.understander: .needsDownload(bytes: 1)]), onboardingCompleted: true, trigger: .foreground), .block(missing: [.understander]))
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.understander: .verifyFailed]), onboardingCompleted: true, trigger: .coldLaunch), .block(missing: [.understander]))
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.translation("id"): .needsDownload(bytes: nil)]), onboardingCompleted: false, trigger: .coldLaunch), .onboarding)
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.understander: .downloading(progress: 0.4)]), onboardingCompleted: true, trigger: .foreground), .showProgress)
        // 印尼语听写不可用是例外，不阻断
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.speech("id"): .unavailable("听印尼语暂不可用")]), onboardingCompleted: true, trigger: .foreground), .open)
        // 但 unavailable 用在模型上必须阻断
        XCTAssertEqual(ReadinessGate.decide(tier: .a8GB, status: full([.understander: .unavailable("x")]), onboardingCompleted: true, trigger: .foreground), .block(missing: [.understander]))
        XCTAssertEqual(ReadinessGate.decide(tier: .unsupported, status: full(), onboardingCompleted: true, trigger: .coldLaunch), .unsupportedDevice)
        let multi = ReadinessGate.decide(tier: .a8GB, status: full([.understander: .paused(progress: 0.2), .touristSpeech: .needsDownload(bytes: nil)]), onboardingCompleted: true, trigger: .foreground)
        guard case .block(let m) = multi else { return XCTFail() }
        XCTAssertEqual(Set(m), [.understander, .touristSpeech])
    }

    func testDeviceTier() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertEqual(DeviceTier.from(physicalMemory: 8 * gb), .a8GB)
        XCTAssertEqual(DeviceTier.from(physicalMemory: 6 * gb - gb / 4), .b6GB)
        XCTAssertEqual(DeviceTier.from(physicalMemory: 4 * gb - gb / 4), .unsupported, "4GB 默认关闭")
        XCTAssertEqual(DeviceTier.from(physicalMemory: 4 * gb - gb / 4, c4GBEnabled: true), .c4GB)
        XCTAssertEqual(DeviceTier.from(physicalMemory: 3 * gb), .unsupported)
    }

    let entry = ModelManifestEntry(tier: "b6GB", id: "m1", url: "https://x/m.gguf", bytes: 1_000, sha256: "ABC")

    func testWifiHappyPath() {
        var m = DownloadMachine(entry: entry)
        m.handle(.start(network: .wifi, freeBytes: 10_000))
        XCTAssertEqual(m.state, .downloading(received: 0, total: 1_000))
        m.handle(.progress(received: 400))
        XCTAssertEqual(m.readiness, .downloading(progress: 0.4))
        m.handle(.finished); XCTAssertEqual(m.state, .verifying)
        m.handle(.verified(sha256: "abc")); XCTAssertEqual(m.state, .installed); XCTAssertEqual(m.readiness, .ready)
    }

    func testCellularNeedsConfirmation() {
        var m = DownloadMachine(entry: entry)
        m.handle(.start(network: .cellular, freeBytes: 10_000))
        XCTAssertEqual(m.state, .awaitingCellularConfirmation)
        m.handle(.confirmCellular)
        XCTAssertEqual(m.state, .downloading(received: 0, total: 1_000))
        XCTAssertTrue(m.policy.cellularConfirmed)
    }

    func testNoNetworkAndSpace() {
        var m = DownloadMachine(entry: entry)
        m.handle(.start(network: .none, freeBytes: 10_000)); XCTAssertEqual(m.state, .failed("network"))
        var s = DownloadMachine(entry: entry)
        s.handle(.start(network: .wifi, freeBytes: 500))
        XCTAssertEqual(s.state, .notEnoughSpace(needed: 600)) // 1000×1.1−500
        XCTAssertEqual(s.readiness, .notEnoughSpace(needed: 600))
    }

    func testResume() {
        var m = DownloadMachine(entry: entry)
        m.handle(.start(network: .wifi, freeBytes: 10_000)); m.handle(.progress(received: 700))
        m.handle(.interrupted(hasResumeData: true))
        XCTAssertEqual(m.state, .paused(received: 700, total: 1_000, hasResumeData: true))
        m.handle(.resume(network: .none)); XCTAssertEqual(m.state, .paused(received: 700, total: 1_000, hasResumeData: true))
        m.handle(.resume(network: .cellular)); XCTAssertEqual(m.state, .awaitingCellularConfirmation)
        var w = DownloadMachine(entry: entry)
        w.handle(.start(network: .wifi, freeBytes: 10_000)); w.handle(.progress(received: 700)); w.handle(.interrupted(hasResumeData: true))
        w.handle(.resume(network: .wifi)); XCTAssertEqual(w.state, .downloading(received: 700, total: 1_000))
        var n = DownloadMachine(entry: entry)
        n.handle(.start(network: .wifi, freeBytes: 10_000)); n.handle(.progress(received: 700)); n.handle(.interrupted(hasResumeData: false))
        XCTAssertEqual(n.state, .paused(received: 0, total: 1_000, hasResumeData: false))
        // 续传时空间只需剩余部分
        var r = DownloadMachine(entry: entry)
        r.handle(.start(network: .wifi, freeBytes: 10_000)); r.handle(.progress(received: 900)); r.handle(.interrupted(hasResumeData: true))
        r.handle(.start(network: .wifi, freeBytes: 200)); XCTAssertEqual(r.state, .downloading(received: 900, total: 1_000))
    }

    func testVerifyRetryOnce() {
        var m = DownloadMachine(entry: entry)
        m.handle(.start(network: .wifi, freeBytes: 10_000)); m.handle(.finished); m.handle(.verified(sha256: "bad"))
        XCTAssertEqual(m.state, .downloading(received: 0, total: 1_000))
        m.handle(.finished); m.handle(.verified(sha256: "bad"))
        XCTAssertEqual(m.state, .verifyFailed(retriesLeft: 0)); XCTAssertEqual(m.readiness, .verifyFailed)
    }

    func testSHA256() throws {
        XCTAssertEqual(SHA256Hasher.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hasher.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Hasher.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        let big = Data(repeating: 0x61, count: 1_000_000)
        XCTAssertEqual(SHA256Hasher.hex(big), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID()).bin")
        try big.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SHA256Hasher.hex(fileAt: url, chunkSize: 4096 + 7), SHA256Hasher.hex(big))
    }
}
