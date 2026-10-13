import XCTest
@testable import SoloCore

private actor Replay: SoloByteStream {
    var input: Data
    var requests: [Data] = []
    init(_ input: Data) { self.input = input }
    func send(_ data: Data) { requests.append(data) }
    func receive(_ count: Int) throws -> Data {
        guard input.count >= count else { throw SoloError.invalid("truncated") }
        let data = Data(input.prefix(count)); input.removeFirst(count); return data
    }
}
final class TransferTests: XCTestCase {
    func frame(_ data: Data) -> Data {
        // Independent fixture serializer, derived from the actual wire capture.
        Data("<hSTCP".utf8) + SoloFrame.little(data.count) + Data([0,62]) + data + Data("<STCP".utf8) + SoloFrame.little(data.reduce(0) { ($0 + Int($1)) & 65535 }, bytes: 2) + Data([62])
    }
    func testLiteralHandshakeAndChecksumRejection() throws {
        XCTAssertEqual(try SoloFrame.encode(payload: SoloFrame.handshake).map { String(format: "%02x", $0) }.joined(), "3c685354435008000000003e00000000060800003c535443500e003e")
        var corrupt = frame(Data([1,2,3])); corrupt[corrupt.count - 2] ^= 1
        XCTAssertThrowsError(try SoloFrame.decode(corrupt))
        XCTAssertThrowsError(try SoloFrame.command(path: "1:/mem/../config.xrz"))
    }
    func testRealChunkSizesAndDisconnection() async throws {
        let bytes = Data((0..<95114).map { UInt8(truncatingIfNeeded: $0) })
        var size = Data(repeating: 0, count: 64); size.replaceSubrange(16..<20, with: SoloFrame.little(95114))
        let prefix = frame(Data([0,0,0,0,6,9,0,0])) + frame(Data(repeating: 0, count: 64)) + frame(size)
        let input = prefix + frame(SoloFrame.little(0) + bytes.prefix(65472)) + frame(SoloFrame.little(65472) + bytes.dropFirst(65472))
        let stream = Replay(input); var received = Data()
        try await SoloTransfer(stream: stream).read(path: "1:/mem/a_0950.xrz", expectedSize: 95114) { data, _, _ in received.append(data) }
        XCTAssertEqual(received, bytes)
        let requests = await stream.requests
        XCTAssertEqual(try SoloFrame.decode(requests.last!), Data([0xc0,0xff,0,0]))
        do { try await SoloTransfer(stream: Replay(Data(input.dropLast(10)))).read { _,_,_ in }; XCTFail("Truncated file must fail") }
        catch { }
    }
    func testSizeMismatchStopsBeforeAnyFileData() async throws {
        var size = Data(repeating: 0, count: 64); size[16] = 5
        let input = frame(Data([0,0,0,0,6,9,0,0])) + frame(Data(repeating: 0, count: 64)) + frame(size)
        var delivered = false
        do { try await SoloTransfer(stream: Replay(input)).read(expectedSize: 10) { _,_,_ in delivered = true }; XCTFail("Should reject mismatch") }
        catch { XCTAssertFalse(delivered) }
    }
}
