import XCTest
import Network
@testable import SoloCore

final class SoloSocketTests: XCTestCase {
    func testActualUDPDiscoveryBytesRoundTrip() async throws {
        let queue = DispatchQueue(label: "SoloSocketTests.udp")
        let ready = expectation(description: "UDP server ready")
        let request = expectation(description: "Device receives aim-ka")
        let listener = try NWListener(using: .udp)
        defer { listener.cancel() }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receiveMessage { data, _, _, error in
                XCTAssertNil(error)
                XCTAssertEqual(data, Data("aim-ka".utf8))
                request.fulfill()
                connection.send(content: Data("Solo 2 Tom".utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 3)
        let port = try XCTUnwrap(listener.port)
        // Exercise the production default routing, without a test-only override.
        let client = SoloSocket(port: port.rawValue, udp: true, host: "127.0.0.1", timeout: 2)
        defer { client.close() }
        try await client.connect()
        try await client.send(Data("aim-ka".utf8))
        let data = try await client.datagram()
        XCTAssertEqual(data, Data("Solo 2 Tom".utf8))
        await fulfillment(of: [request], timeout: 1)
    }

    func testTCPTimeoutNamesReceiveStageAndPersistsPath() async throws {
        let queue = DispatchQueue(label: "SoloSocketTests.tcp")
        let ready = expectation(description: "TCP server ready")
        let listener = try NWListener(using: .tcp)
        defer { listener.cancel() }
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            // Keep the peer open without sending, then release it after the test.
            queue.asyncAfter(deadline: .now() + 2) { connection.cancel() }
        }
        listener.start(queue: queue)
        await fulfillment(of: [ready], timeout: 3)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try SoloConnectionLog(directory: root, operation: "test", appVersion: "test")
        let client = SoloSocket(port: try XCTUnwrap(listener.port).rawValue, host: "127.0.0.1",
                                timeout: 0.15, trace: { log.record($0, $1) })
        defer { client.close() }
        try await client.connect(timeout: 2)
        do { _ = try await client.receive(12); XCTFail("Idle peer must time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("TCP 接收")) }
        let text = try String(contentsOf: log.url)
        XCTAssertTrue(text.contains("TCP.timeout"))
        XCTAssertTrue(text.contains("local="))
    }
}
