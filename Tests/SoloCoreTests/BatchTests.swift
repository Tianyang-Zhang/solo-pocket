import XCTest
@testable import SoloCore

final class BatchTests: XCTestCase {
    func testLegacyBatchWithoutRenamedFileFieldStillUsesOriginalPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour\na_0001.xrz,3,11/10/2026,12:00:00\n".utf8))
        let created = try await store.create(metadata: BatchMetadata(title: "Old batch"), sessions: sessions)
        let state = root.appendingPathComponent(".state/" + created.id.uuidString + ".json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: state)) as! [String: Any]
        var files = json["files"] as! [[String: Any]]
        files[0].removeValue(forKey: "localFilename"); json["files"] = files
        try JSONSerialization.data(withJSONObject: json).write(to: state)
        let loaded = try await store.load(created.id)
        XCTAssertEqual(loaded.files[0].filename, "a_0001.xrz")
        let folder = try await store.folder(loaded)
        try Data("abc".utf8).write(to: folder.appendingPathComponent("a_0001.xrz"))
        let completed = try await store.recordDownloaded(loaded.id, sessionID: sessions[0].id)
        try await store.verifyLocal(completed)
        let exported = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("batch.json"))) as! [String: Any]
        XCTAssertEqual(exported["schemaVersion"] as? Int, 1, "Keep old export format for existing Drive receipts")
        let csv = try String(contentsOf: folder.appendingPathComponent("sessions.csv"))
        XCTAssertFalse(csv.contains("device_file"))
    }

    func testRenamedFilesKeepSourceMappingAndSurviveSameTimestampCollision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour\na_0001.xrz,3,11/10/2026,16:55:28\na_0002.xrz,3,11/10/2026,16:55:28\n".utf8))
        let batch = try await store.create(metadata: BatchMetadata(title: "Ride", driver: "Tom", vehicle: "Bike"), sessions: sessions)
        let folder = try await store.folder(batch)
        let names = ["Tom_2026-10-11_16-55-28.xrz", "Tom_2026-10-11_16-55-28_2.xrz"]
        for (index, session) in sessions.enumerated() {
            try Data("abc".utf8).write(to: folder.appendingPathComponent(names[index]))
            _ = try await store.recordDownloaded(batch.id, sessionID: session.id)
        }
        let restarted = try BatchStore(root: root), loaded = try await restarted.load(batch.id)
        try await restarted.verifyLocal(loaded)
        XCTAssertEqual(loaded.files.map { $0.session.devicePath }, ["1:/mem/a_0001.xrz", "1:/mem/a_0002.xrz"])
        let csv = try String(contentsOf: folder.appendingPathComponent("sessions.csv"))
        for name in names + ["a_0001.xrz", "a_0002.xrz"] { XCTAssertTrue(csv.contains(name)) }
    }

    func testFolderPreviewMatchesDateRangeAndAvoidsExistingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour\na_0001.xrz,3,11/10/2026,12:00:00\na_0002.xrz,3,10/10/2026,12:00:00\n".utf8))
        let metadata = BatchMetadata(title: "Title stays in metadata", driver: "张/三", vehicle: "KTM 390\nDuke", notes: "Not part of the folder")
        let base = "2026-10-10_至_2026-10-11_张_三_KTM_390_Duke"
        try Data("existing file".utf8).write(to: root.appendingPathComponent(base))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent(base + "_2").path, withDestinationPath: "missing-target")
        let preview = try await store.suggestedFolderName(metadata: metadata, sessions: sessions)
        XCTAssertEqual(preview, base + "_3")
        let batch = try await store.create(metadata: metadata, sessions: sessions)
        XCTAssertEqual(batch.folderName, preview)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(base)), "existing file")
        let reloaded = try await store.load(batch.id)
        XCTAssertEqual(reloaded.folderName, preview)
    }

    func testLongChineseNamesFitFilesystemAndKeepRecordingDate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour\na_0001.xrz,3,11/10/2026,12:00:00\n".utf8))
        let metadata = BatchMetadata(title: "Batch", driver: String(repeating: "车手", count: 100), vehicle: String(repeating: "车型", count: 100))
        let batch = try await store.create(metadata: metadata, sessions: sessions)
        XCTAssertTrue(batch.folderName.hasPrefix("2026-10-11_"))
        XCTAssertLessThan(batch.folderName.utf8.count, 255)
        let folder = try await store.folder(batch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("batch.json").path))
    }

    func testChangingParentOnlyAffectsNewBatchesAndSurvivesRestart() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("default"), parent = base.appendingPathComponent("chosen")
        let state = base.appendingPathComponent("state")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let store = try BatchStore(root: root, stateRoot: state)
        let sessions = try Session.parse(Data("name,size,date,hour,nlap,best,track_name,test_dur\na_0001.xrz,3,11/10/2026,12:00:00,2,35123,Kinsmen,60000\n".utf8))
        let first = try await store.create(metadata: BatchMetadata(title: "First"), sessions: sessions)
        try await store.setDownloadRoot(parent)
        let second = try await store.create(metadata: BatchMetadata(title: "Second"), sessions: sessions)
        let firstFolder = try await store.folder(first), secondFolder = try await store.folder(second)
        XCTAssertEqual(firstFolder.deletingLastPathComponent().standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertEqual(secondFolder.deletingLastPathComponent().standardizedFileURL.path, parent.standardizedFileURL.path)
        try Data("abc".utf8).write(to: secondFolder.appendingPathComponent(second.files[0].filename))
        _ = try await store.recordDownloaded(second.id, sessionID: sessions[0].id)
        let restarted = try BatchStore(root: root, stateRoot: state)
        let selectedRoot = try await restarted.downloadRoot()
        XCTAssertEqual(selectedRoot.standardizedFileURL.path, parent.standardizedFileURL.path)
        let loaded = try await restarted.load(second.id)
        try await restarted.verifyLocal(loaded)
        try await restarted.setDownloadRoot(nil)
        let stillThere = try await restarted.folder(loaded)
        XCTAssertEqual(stillThere.standardizedFileURL.path, secondFolder.standardizedFileURL.path)
        let third = try await restarted.create(metadata: BatchMetadata(title: "Third"), sessions: sessions)
        let thirdFolder = try await restarted.folder(third)
        XCTAssertEqual(thirdFolder.deletingLastPathComponent().standardizedFileURL.path, root.standardizedFileURL.path)
        let exported = try String(contentsOf: secondFolder.appendingPathComponent("batch.json"))
        XCTAssertFalse(exported.contains("localRootBookmark"))
        XCTAssertFalse(exported.contains(parent.path))
    }

    func testInvalidOrMissingParentDoesNotSilentlyFallBack() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("default"), chosen = base.appendingPathComponent("chosen")
        let store = try BatchStore(root: root)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        try await store.setDownloadRoot(chosen)
        let file = base.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        do { try await store.setDownloadRoot(file); XCTFail("Regular files cannot be roots") } catch { }
        let selected = try await store.downloadRoot()
        XCTAssertEqual(selected.standardizedFileURL.path, chosen.standardizedFileURL.path)
        try FileManager.default.removeItem(at: chosen)
        do { _ = try await store.downloadRoot(); XCTFail("Missing root must not fall back") } catch { }
    }

    func testBatchSurvivesRestartAndMetadataTravelsWithFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BatchStore(root: root)
        let sessions = try Session.parse(Data("name,size,date,hour,nlap,best,track_name,test_dur\na_0001.xrz,3,11/10/2026,12:00:00,2,35123,Kinsmen,60000\n".utf8))
        let m = BatchMetadata(title: "Tom / Kinsmen", driver: "Tom", vehicle: "Bike", notes: "test, note")
        let first = try await store.create(metadata: m, sessions: sessions)
        let second = try await store.create(metadata: m, sessions: sessions)
        XCTAssertEqual(first.folderName, "2026-10-11_Tom_Bike")
        XCTAssertEqual(second.folderName, "2026-10-11_Tom_Bike_2")
        var upper = m; upper.driver = "TOM"
        let upperPreview = try await store.suggestedFolderName(metadata: upper, sessions: sessions)
        XCTAssertEqual(upperPreview, "2026-10-11_TOM_Bike_3", "Case-only differences must not reuse a folder on case-insensitive storage")
        XCTAssertNotEqual(first.folderName, second.folderName)
        let folder = try await store.folder(first)
        XCTAssertEqual(first.files[0].filename, "Tom_2026-10-11_12-00-00.xrz")
        try Data("abc".utf8).write(to: folder.appendingPathComponent(first.files[0].filename))
        _ = try await store.recordDownloaded(first.id, sessionID: sessions[0].id)
        let restarted = try BatchStore(root: root), loaded = try await restarted.load(first.id)
        XCTAssertTrue(loaded.downloadComplete)
        XCTAssertEqual(loaded.metadata, m)
        XCTAssertEqual(loaded.files[0].sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try await restarted.verifyLocal(loaded)
        let csv = try String(contentsOf: folder.appendingPathComponent("sessions.csv"), encoding: .utf8)
        XCTAssertTrue(csv.contains("test, note"))
        let json = try String(contentsOf: folder.appendingPathComponent("batch.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("resumableURL"))
        try Data("bad".utf8).write(to: folder.appendingPathComponent(first.files[0].filename))
        do { try await restarted.verifyLocal(loaded); XCTFail("Changed bytes must fail") } catch { }
    }
}
