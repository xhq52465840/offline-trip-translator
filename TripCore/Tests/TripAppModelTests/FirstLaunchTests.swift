import XCTest
import TripCore
@testable import TripAppModel

final class FirstLaunchTests: XCTestCase {
    func testDefaults() {
        XCTAssertTrue(FirstLaunch.defaults(preferred: ["zh-Hans-CN"]) == ("zh-Hans", "id"))
        XCTAssertTrue(FirstLaunch.defaults(preferred: ["en-US"]) == ("en", "id"))
        XCTAssertTrue(FirstLaunch.defaults(preferred: ["id-ID"]) == ("id", "zh-Hans"))
        XCTAssertTrue(FirstLaunch.defaults(preferred: ["fr-FR"]) == ("zh-Hans", "id"))
    }
    func testPickNeverSame() {
        XCTAssertTrue(FirstLaunch.pick(me: "id", them: "id", changed: .me) == ("id", "zh-Hans"))
        XCTAssertTrue(FirstLaunch.pick(me: "zh-Hans", them: "zh-Hans", changed: .them) == ("id", "zh-Hans"))
        XCTAssertTrue(FirstLaunch.pick(me: "en", them: "id", changed: .me) == ("en", "id"))
    }
    func testDownloadLine() {
        XCTAssertEqual(FirstLaunch.downloadLine(bytes: 986_048_640), "理解能力 约 986 MB")
    }
}
