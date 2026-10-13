import XCTest
@testable import SoloCore

private actor MockHTTP {
    var replies: [HTTPResult]
    var requests: [URLRequest] = []
    init(_ replies: [HTTPResult]) { self.replies = replies }
    func send(_ request: URLRequest) throws -> HTTPResult {
        requests.append(request)
        guard !replies.isEmpty else { throw SoloError.invalid("Unexpected request") }
        return replies.removeFirst()
    }
}
final class DriveTests: XCTestCase {
    func testBatchUploaderUsesRenamedFilesAndStableReceiptKeys() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour\na_0001.xrz,3,11/10/2026,16:55:28\n".utf8))
        var batch = try await store.create(metadata: BatchMetadata(title: "Ride", driver: "Tom", vehicle: "Bike"), sessions: sessions)
        let folder = try await store.folder(batch)
        let renamed = "Tom_2026-10-11_16-55-28.xrz"
        try Data("abc".utf8).write(to: folder.appendingPathComponent(renamed))
        batch = try await store.recordDownloaded(batch.id, sessionID: sessions[0].id)
        batch.driveFolderID = "batch-folder"; batch.driveAccountID = "account"; batch.driveParentID = "parent"
        let names = [renamed, "batch.json", "sessions.csv"], ids = ["data-id", "json-id", "csv-id"]
        for (name, id) in zip(names, ids) { batch.uploads[name] = UploadReceipt(fileID: id) }
        try await store.save(batch)
        var replies = [HTTPResult(data: Data("{\"id\":\"batch-folder\",\"mimeType\":\"application/vnd.google-apps.folder\",\"parents\":[\"parent\"]}".utf8), status: 200)]
        for (name, id) in zip(names, ids) {
            let digest = try FileDigest.read(folder.appendingPathComponent(name))
            replies.append(HTTPResult(data: try JSONSerialization.data(withJSONObject: ["id":id, "size":String(digest.bytes), "md5Checksum":digest.md5, "parents":["batch-folder"], "trashed":false]), status: 200))
        }
        let mock = MockHTTP(replies)
        let drive = DriveClient(token: { "test-token" }, http: { try await mock.send($0) })
        try await BatchUploader(drive: drive, store: store).upload(id: batch.id, accountID: "account", parentID: "parent") { _, _ in }
        let finished = try await store.load(batch.id)
        XCTAssertNotNil(finished.uploadedAt)
        XCTAssertEqual(Set(finished.uploads.keys), Set(names))
        XCTAssertTrue(finished.uploads.values.allSatisfy(\.complete))
        let requests = await mock.requests
        XCTAssertEqual(requests.count, 4, "Renamed files must resume using their saved IDs, without creating duplicate uploads")
    }

    func remote(_ digest: (bytes: Int, sha256: String, md5: String), md5: String? = nil) throws -> HTTPResult {
        HTTPResult(data: try JSONSerialization.data(withJSONObject: ["id":"stable-id", "size":String(digest.bytes), "md5Checksum":md5 ?? digest.md5, "parents":["batch-folder"], "trashed":false]), status: 200)
    }
    func testResumesFromServerOffsetAndChecksFinalDigest() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 7, count: 600000).write(to: file)
        let digest = try FileDigest.read(file)
        let mock = MockHTTP([HTTPResult(data: Data(), status:404), HTTPResult(data:Data(), status:308, headers:["Range":"bytes=0-262143"]), HTTPResult(data:Data(), status:200), try remote(digest)])
        let client = DriveClient(token: { "test-token" }, http: { try await mock.send($0) })
        var receipt = UploadReceipt(fileID:"stable-id"); receipt.resumableURL = URL(string:"https://www.googleapis.com/upload/drive/v3/files?upload_id=test")
        var saved: UploadReceipt?
        let result = try await client.upload(url: file, parent:"batch-folder", receipt:receipt, checkpoint: { saved = $0 }, progress: { _ in })
        XCTAssertTrue(result.complete); XCTAssertTrue(saved?.complete == true)
        let requests = await mock.requests
        XCTAssertEqual(requests[1].value(forHTTPHeaderField:"Content-Range"), "bytes */600000")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField:"Content-Range"), "bytes 262144-599999/600000")
        XCTAssertEqual(requests[2].httpBody?.count, 337856)
    }
    func testLostCompletionResponseDoesNotCreateDuplicate() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to:file)
        let mock = MockHTTP([try remote(FileDigest.read(file))])
        let client = DriveClient(token:{ "test-token" }, http:{ try await mock.send($0) })
        let result = try await client.upload(url:file, parent:"batch-folder", receipt:UploadReceipt(fileID:"stable-id"), checkpoint:{ _ in }, progress:{ _ in })
        XCTAssertTrue(result.complete)
        let requests = await mock.requests
        XCTAssertEqual(requests.count,1); XCTAssertEqual(requests[0].httpMethod,"GET")
    }
    func testWrongRemoteChecksumIsNotMarkedSuccessful() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        try Data("abc".utf8).write(to:file)
        let mock = MockHTTP([try remote(FileDigest.read(file), md5:"wrong")])
        let client = DriveClient(token:{ "test-token" }, http:{ try await mock.send($0) })
        var marked = false
        do {
            _ = try await client.upload(url:file, parent:"batch-folder", receipt:UploadReceipt(fileID:"stable-id"), checkpoint:{ marked = $0.complete }, progress:{ _ in })
            XCTFail("Must reject wrong checksum")
        } catch { XCTAssertFalse(marked) }
    }
    func testNoRangeMeansNoBytesReceivedAndBadRangeRejected() throws {
        XCTAssertEqual(try DriveClient.resumeOffset(nil,size:100),0)
        XCTAssertEqual(try DriveClient.resumeOffset("bytes=0-42",size:100),43)
        XCTAssertThrowsError(try DriveClient.resumeOffset("bytes=0-999",size:100))
        XCTAssertThrowsError(try DriveClient.resumeOffset("bytes=9-12",size:100))
    }
}
