import XCTest
@testable import SoloCore

final class SessionTests: XCTestCase {
    func testSyntheticDeviceListShowsHumanMetadata() throws {
        let url = Bundle.module.url(forResource: "sessions", withExtension: "csv", subdirectory: "Fixtures")!
        let sessions = try Session.parse(Data(contentsOf: url))
        XCTAssertEqual(sessions.count, 46)
        let s = try XCTUnwrap(sessions.first { $0.filename == "a_0939.xrz" })
        XCTAssertEqual(s.devicePath, "1:/mem/a_0939.xrz")
        XCTAssertEqual(s.dateLabel, "2026-01-02")
        XCTAssertEqual(s.time, "10:15:30")
        XCTAssertEqual(s.title, "2026-01-02  10:15:30")
        XCTAssertEqual(s.laps, 13)
        XCTAssertEqual(s.bestLabel, "0:36.546")
        XCTAssertEqual(s.durationLabel, "8:29")
        XCTAssertEqual(s.track, "Demo Circuit")
        XCTAssertEqual(s.size, 1110564)
        XCTAssertEqual(sessions.first?.bestLabel, "—")
    }
    func testCSVQuotedCommasAndInvalidPaths() throws {
        let data = Data("name,size,date,hour,nlap,best,track_name,test_dur\r\na_0001.xrz,12,11/10/2026,12:00:00,2,61234,\"Track, A\",90000\r\n../evil.xrz,10,,,,,,\r\na_0002.hrz,10,,,,,,\r\n".utf8)
        let sessions = try Session.parse(data)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.track, "Track, A")
        XCTAssertThrowsError(try Session.parse(Data("not a list".utf8)))
    }
    func testBestLapFilterHidesMissingZeroAndNegativeTimesWithoutDroppingRecords() throws {
        let data = Data("""
        name,size,date,hour,nlap,best
        timed.xrz,12,11/10/2026,12:00:00,3,36546
        empty.xrz,12,11/10/2026,12:10:00,0,
        zero.xrz,12,11/10/2026,12:20:00,0,0
        negative.xrz,12,11/10/2026,12:30:00,0,-1
        invalid.xrz,12,11/10/2026,12:40:00,0,unknown
        """.utf8)
        let sessions = try Session.parse(data)
        XCTAssertEqual(sessions.filter(\.hasBestLap).map(\.filename), ["timed.xrz"])
        XCTAssertEqual(sessions.count, 5, "Filtering must not discard data during parsing")
    }
}
