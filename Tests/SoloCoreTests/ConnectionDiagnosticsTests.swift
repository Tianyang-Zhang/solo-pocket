import XCTest
@testable import SoloCore

final class ConnectionDiagnosticsTests: XCTestCase {
    func testDiagnosticLogPersistsWithoutCloudOrSessionData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try SoloConnectionLog(directory: root, operation: "scan", appVersion: "test")
        log.record("udp.state", "waiting localNetworkDenied")
        log.record("operation.failed", "UDP 接收超时")
        let saved = try String(contentsOf: log.url)
        XCTAssertTrue(saved.contains("waiting localNetworkDenied"))
        XCTAssertTrue(saved.contains("UDP 接收超时"))
        XCTAssertTrue(saved.contains("app=test"))
        XCTAssertFalse(saved.contains("Google"))
        let other = try SoloConnectionLog(directory: root, operation: "scan", appVersion: "test")
        XCTAssertNotEqual(log.url, other.url)
    }
}
