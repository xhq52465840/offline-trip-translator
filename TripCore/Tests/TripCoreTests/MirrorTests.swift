import XCTest
@testable import TripCore

final class ManualClock { var t = Date(timeIntervalSince1970: 0); func now() -> Date { t } }

final class MirrorTests: XCTestCase {
    let payload = Data((0..<5000).map { UInt8($0 % 251) })
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("mirrors-\(UUID())") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    let ms = [ModelMirror(id: "cn", url: "https://cn.example.com/m.gguf"), ModelMirror(id: "global", url: "https://global.example.com/m.gguf"),
              ModelMirror(id: "hf", url: "https://huggingface.co/m.gguf")]

    func make(clock: ManualClock = ManualClock(), sha: String? = nil, mirrors: [ModelMirror]? = nil) -> (ModelDownloader, FakeTransport) {
        let t = FakeTransport(payload: payload)
        let e = ModelManifestEntry(tier: "b6GB", id: "m1", url: "https://legacy.example.com/m.gguf", bytes: Int64(payload.count),
                                   sha256: sha ?? SHA256Hasher.hex(payload), mirrors: mirrors ?? ms)
        return (ModelDownloader(entry: e, directory: dir, transport: t, environment: FakeEnv(), now: clock.now), t)
    }

    func testUsesFirstMirrorAndLegacyFallback() {
        let (d, t) = make(); d.start()
        XCTAssertEqual(t.starts[0].url.host, "cn.example.com")
        let (d2, t2) = make(mirrors: []); d2.start()
        XCTAssertEqual(t2.starts[0].url.host, "legacy.example.com", "没有镜像时用旧的 url 字段")
        _ = d; _ = d2
    }

    func testFailureWithoutResumeSwitchesImmediately() {
        let (d, t) = make(); d.start()
        t.onFailed?(nil)
        XCTAssertEqual(t.starts.count, 2); XCTAssertEqual(t.starts[1].url.host, "global.example.com"); XCTAssertNil(t.starts[1].resume)
        XCTAssertEqual(d.currentMirror.id, "global")
        t.deliver(); XCTAssertEqual(d.machine.state, .installed)
    }

    func testFailureWithResumeRetriesSameMirrorThenSwitches() {
        let (d, t) = make(); d.start()
        t.onProgress?(1000); t.onFailed?(Data("r-cn".utf8))
        XCTAssertEqual(t.starts[1].url.host, "cn.example.com"); XCTAssertEqual(t.starts[1].resume, Data("r-cn".utf8))
        t.onFailed?(Data("r-cn2".utf8))                         // 第二次失败：换镜像，且不带 cn 的 resume data
        XCTAssertEqual(t.starts[2].url.host, "global.example.com"); XCTAssertNil(t.starts[2].resume, "跨镜像不续传")
        XCTAssertEqual(d.mirrors.resumeData["cn"], Data("r-cn2".utf8), "cn 的续传数据保留给 cn")
    }

    func testAllMirrorsFailStopsThenUserRetryStartsNewRound() {
        let (d, t) = make(); d.start()
        t.onFailed?(nil); t.onFailed?(nil); t.onFailed?(nil)
        XCTAssertEqual(t.starts.count, 3)
        XCTAssertEqual(d.machine.state, .paused(received: 0, total: 5000, hasResumeData: false))
        d.resume()
        XCTAssertEqual(t.starts.count, 4); XCTAssertEqual(t.starts[3].url.host, "cn.example.com")
    }

    func testSlowMirrorSwitchesKeepingItsResumeData() {
        let c = ManualClock(); let (d, t) = make(clock: c); d.start()
        var bytes: Int64 = 0
        for _ in 0..<40 { c.t += 1; bytes += 10_000; t.onProgress?(bytes) }   // 10 KB/s，远低于阈值
        XCTAssertEqual(t.starts.count, 2, "过慢切换")
        XCTAssertEqual(t.starts[1].url.host, "global.example.com"); XCTAssertNil(t.starts[1].resume)
        XCTAssertEqual(d.mirrors.resumeData["cn"], Data("resume-token".utf8))
        XCTAssertEqual(d.mirrors.switches.last?.reason, .slow)
        t.deliver(); XCTAssertEqual(d.machine.state, .installed)
    }

    func testFastMirrorNotSwitched() {
        let c = ManualClock(); let (d, t) = make(clock: c); d.start()
        var bytes: Int64 = 0
        for _ in 0..<60 { c.t += 1; bytes += 2_000_000; t.onProgress?(bytes) }
        XCTAssertEqual(t.starts.count, 1); _ = d
    }

    func testSlowSwitchDoesNotPingPong() {
        let c = ManualClock(); let (d, t) = make(clock: c, mirrors: Array(ms.prefix(2))); d.start()
        var bytes: Int64 = 0
        for _ in 0..<200 { c.t += 1; bytes += 1_000; t.onProgress?(bytes) }
        XCTAssertEqual(t.starts.count, 2, "两个都慢时只切一次，不来回跳"); _ = d
    }

    func testBadHashOnMirrorRetriesOnNextMirror() {
        let (d, t) = make(); d.start()
        var bad = payload; bad[0] ^= 0xFF
        t.deliver(bad)
        XCTAssertEqual(t.starts.count, 2); XCTAssertEqual(t.starts[1].url.host, "global.example.com")
        t.deliver(); XCTAssertEqual(d.machine.state, .installed)
    }

    func testUserPauseDoesNotSwitch() {
        let (d, t) = make(); d.start(); t.onProgress?(100)
        d.pause(); XCTAssertEqual(d.machine.state, .paused(received: 100, total: 5000, hasResumeData: true))
        XCTAssertEqual(t.starts.count, 1)
        d.resume(); XCTAssertEqual(t.starts[1].url.host, "cn.example.com"); XCTAssertEqual(t.starts[1].resume, Data("resume-token".utf8))
    }

    func testBundledManifestHasMirrorsWithGitHubReleaseLast() throws {
        let m = try ModelManifest.bundled()
        for e in m.models {
            XCTAssertEqual(e.orderedMirrors.map(\.id), ["cn", "global", "gh"])
            XCTAssertEqual(e.orderedMirrors.last?.url, e.url)
            XCTAssertEqual(e.sha256.count, 64)
        }
    }
}
