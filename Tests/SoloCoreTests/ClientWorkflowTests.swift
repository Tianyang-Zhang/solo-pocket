import XCTest
import Network
@testable import SoloCore

/// A local peer exercises the public client workflow, including the automatic
/// empty TCP preflight. It cannot reproduce iPhone's privacy permission dialog.
private final class LocalSoloPeer: @unchecked Sendable {
    let queue = DispatchQueue(label: "SoloClientTests.peer")
    let tcp = try! NWListener(using: .tcp)
    let udp = try! NWListener(using: .udp)
    private var connections: [NWConnection] = []
    private var tcpCount = 0

    func start(ready: XCTestExpectation, emptyProbe: XCTestExpectation, transfer: XCTestExpectation,
               csv: Data, discoveryReply: Data) {
        tcp.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        udp.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        tcp.newConnectionHandler = { [self] connection in
            tcpCount += 1
            let index = tcpCount
            connections.append(connection)
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, complete, error in
                XCTAssertNil(error)
                if index == 1 || index == 3 {
                    XCTAssertTrue(data?.isEmpty ?? true, "Automatic preflight must send no protocol commands")
                    XCTAssertTrue(complete)
                    emptyProbe.fulfill()
                    connection.cancel()
                } else {
                    XCTAssertFalse(data?.isEmpty ?? true, "Transfer must start after preflight and discovery")
                    let body = index == 2 ? csv : Data("abc".utf8)
                    connection.send(content: Self.replies(body), completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        transfer.fulfill()
                    })
                }
            }
        }
        udp.newConnectionHandler = { [self] connection in
            connections.append(connection)
            connection.start(queue: queue)
            connection.receiveMessage { data, _, _, error in
                XCTAssertNil(error)
                XCTAssertGreaterThan(self.tcpCount, 0, "Reading must perform TCP preflight without a separate user action")
                XCTAssertEqual(data, Data("aim-ka".utf8))
                connection.send(content: discoveryReply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        tcp.start(queue: queue); udp.start(queue: queue)
    }
    func stop() {
        queue.sync { connections.forEach { $0.cancel() }; tcp.cancel(); udp.cancel() }
    }
    // Reply bytes match the captured device framing, independently of its encoder.
    private static func replies(_ body: Data) -> Data {
        func little(_ n: Int, count: Int = 4) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
        func frame(_ payload: Data) -> Data {
            Data("<hSTCP".utf8) + little(payload.count) + Data([0, 62]) + payload
                + Data("<STCP".utf8) + little(payload.reduce(0) { ($0 + Int($1)) & 65535 }, count: 2) + Data([62])
        }
        var size = Data(repeating: 0, count: 64)
        size.replaceSubrange(16..<20, with: little(body.count))
        return frame(Data([0,0,0,0,6,9,0,0])) + frame(Data(repeating: 0, count: 64)) + frame(size) + frame(little(0) + body)
    }
}

final class ClientWorkflowTests: XCTestCase {
    func testReadAndDownloadAutomaticallyPreflightThenContinue() async throws {
        try await readAndDownload(discoveryReply: Data("Solo 2 Tom".utf8))
    }
    func testReadAndDownloadWithArbitraryCustomDeviceName() async throws {
        // A valid user-chosen name need not contain "Solo", an owner's name,
        // a serial number, or any Latin characters.
        try await readAndDownload(discoveryReply: Data("车手甲的计时器".utf8))
    }
    func testReadAndDownloadWithUTF16DeviceName() async throws {
        try await readAndDownload(discoveryReply: try XCTUnwrap("SOLO 2 DL - Paddock".data(using: .utf16LittleEndian)))
    }
    func testDiscoveryEncodingDoesNotReplaceProtocolValidation() async throws {
        // Discovery is opaque. Compatibility is established by the TCP
        // handshake and framed responses, not by guessing a name encoding.
        try await readAndDownload(discoveryReply: Data([0xff, 0x80, 0x01, 0x00]))
    }
    private func readAndDownload(discoveryReply: Data) async throws {
        let ready = expectation(description: "Both listeners ready"); ready.expectedFulfillmentCount = 2
        let probes = expectation(description: "Read and download each automatically preflight"); probes.expectedFulfillmentCount = 2
        let transfers = expectation(description: "Both operations continue without a second user action"); transfers.expectedFulfillmentCount = 2
        let csv = Data("name,size,date,hour,nlap,best,track_name,test_dur\na_0001.xrz,3,11/10/2026,12:00:00,2,36546,Kinsmen,60000\n".utf8)
        let peer = LocalSoloPeer(); defer { peer.stop() }
        peer.start(ready: ready, emptyProbe: probes, transfer: transfers, csv: csv, discoveryReply: discoveryReply)
        await fulfillment(of: [ready], timeout: 3)
        let client = SoloClient(host: "127.0.0.1", transferPort: try XCTUnwrap(peer.tcp.port).rawValue,
                                discoveryPort: try XCTUnwrap(peer.udp.port).rawValue)
        // Deliberately do not call checkLocalConnection(): the public workflow owns it.
        let sessions = try await client.sessions()
        XCTAssertEqual(sessions.map(\.title), ["2026-10-11  12:00:00"])
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xrz")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await client.download(try XCTUnwrap(sessions.first), to: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), Data("abc".utf8))
        await fulfillment(of: [probes, transfers], timeout: 3)
    }
}
