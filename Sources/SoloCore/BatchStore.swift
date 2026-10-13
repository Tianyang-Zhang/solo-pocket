import Foundation
import Darwin

public struct BatchMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var driver: String
    public var vehicle: String
    public var notes: String
    public init(title: String = "", driver: String = "", vehicle: String = "", notes: String = "") {
        self.title = title; self.driver = driver; self.vehicle = vehicle; self.notes = notes
    }
}
public struct DownloadedSession: Codable, Identifiable, Sendable {
    public var id: String { session.id }
    public let session: Session
    /// Absent for older batches, whose original on-disk names remain valid.
    public let localFilename: String?
    public var filename: String { localFilename ?? session.filename }
    public var sha256: String?
    public var md5: String?
    public var error: String?
    public var downloaded: Bool { sha256 != nil }
}
public struct UploadReceipt: Codable, Sendable {
    public var fileID: String
    public var resumableURL: URL?
    public var complete: Bool = false
    public init(fileID: String) { self.fileID = fileID }
}
public struct Batch: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let folderName: String
    public let metadata: BatchMetadata
    public var files: [DownloadedSession]
    public var localRootBookmark: Data?
    public var driveAccountID: String?
    public var driveParentID: String?
    public var driveFolderID: String?
    public var uploads: [String: UploadReceipt] = [:]
    public var uploadedAt: Date?
    public var downloadComplete: Bool { !files.isEmpty && files.allSatisfy(\.downloaded) }
    public var completedCount: Int { files.filter(\.downloaded).count }
}

public actor BatchStore {
    public let root: URL
    private let stateRoot: URL
    private let encoder: JSONEncoder
    private var accessedRoots: [Data: ScopedDownloadRoot] = [:]
    private var selectionURL: URL { stateRoot.appendingPathComponent("download-root.bookmark") }
    public init(root: URL, stateRoot: URL? = nil) throws {
        self.root = root; self.stateRoot = stateRoot ?? root.appendingPathComponent(".state", isDirectory: true)
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.stateRoot, withIntermediateDirectories: true)
    }
    public func list() throws -> [Batch] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try FileManager.default.contentsOfDirectory(at: stateRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(Batch.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
    public func load(_ id: UUID) throws -> Batch {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Batch.self, from: Data(contentsOf: stateRoot.appendingPathComponent(id.uuidString + ".json")))
    }
    public func save(_ batch: Batch) throws {
        try encoder.encode(batch).write(to: stateRoot.appendingPathComponent(batch.id.uuidString + ".json"), options: .atomic)
    }
    private func selectedBookmark() throws -> Data? {
        guard FileManager.default.fileExists(atPath: selectionURL.path) else { return nil }
        return try Data(contentsOf: selectionURL)
    }
    private func resolveRoot(_ bookmark: Data?) throws -> URL {
        guard let bookmark else { return root }
        if let cached = accessedRoots[bookmark] {
            try Self.validateRoot(cached.url)
            return cached.url
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
            let scope = ScopedDownloadRoot(url)
            try Self.validateRoot(url)
            accessedRoots[bookmark] = scope
            return url
        } catch {
            throw SoloError.invalid("无法访问原下载目录，请在「设置 → 本地下载目录」重新选择该文件夹。" + error.localizedDescription)
        }
    }
    private static func validateRoot(_ url: URL) throws {
        guard url.isFileURL else { throw SoloError.invalid("请选择手机本地文件夹") }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey])
        guard values.isDirectory == true else { throw SoloError.invalid("请选择文件夹，不能选择文件") }
        guard values.isUbiquitousItem != true else { throw SoloError.invalid("离线下载请在「我的 iPhone」中选择本地文件夹，云端备份可在下载后单独上传。") }
        guard FileManager.default.isWritableFile(atPath: url.path) else { throw SoloError.invalid("此文件夹无法写入，请重新选择可访问的本地目录") }
    }
    public func downloadRoot() throws -> URL { try resolveRoot(selectedBookmark()) }
    public func usesDefaultDownloadRoot() throws -> Bool { try selectedBookmark() == nil }
    public func setDownloadRoot(_ url: URL?) throws {
        guard let url else {
            if FileManager.default.fileExists(atPath: selectionURL.path) { try FileManager.default.removeItem(at: selectionURL) }
            return
        }
        let scope = ScopedDownloadRoot(url)
        try Self.validateRoot(url)
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try bookmark.write(to: selectionURL, options: .atomic)
        accessedRoots[bookmark] = scope
    }
    public func folder(_ batch: Batch) throws -> URL {
        try resolveRoot(batch.localRootBookmark).appendingPathComponent(batch.folderName, isDirectory: true)
    }
    public nonisolated static func folderBaseName(metadata: BatchMetadata, sessions: [Session]) -> String {
        let dates = Set(sessions.map(\.dateLabel).filter {
            $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        }).sorted()
        let date: String
        if let first = dates.first, let last = dates.last {
            date = first == last ? first : "\(first)_至_\(last)"
        } else { date = "日期未知" }
        return "\(date)_\(nameComponent(metadata.driver, fallback: "未填车手"))_\(nameComponent(metadata.vehicle, fallback: "未填车型"))"
    }
    private nonisolated static func nameComponent(_ text: String, fallback: String) -> String {
            let sanitized = text.unicodeScalars.map {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_"
            }.joined().split(separator: "_").joined(separator: "_")
            // Bound bytes (not characters) so Chinese names fit a folder component.
            var value = ""
            for character in sanitized {
                guard value.utf8.count + String(character).utf8.count <= 72 else { break }
                value.append(character)
            }
            return value.isEmpty ? fallback : value
    }
    public nonisolated static func fileNames(metadata: BatchMetadata, sessions: [Session]) -> [String] {
        let driver = nameComponent(metadata.driver, fallback: "未填车手")
        var used = Set<String>()
        return sessions.map { session in
            let date = nameComponent(session.dateLabel, fallback: "日期未知")
            let time = nameComponent(session.time.replacingOccurrences(of: ":", with: "-"), fallback: "时间未知")
            let ext = (session.filename as NSString).pathExtension
            let base = "\(driver)_\(date)_\(time)"
            var name = "\(base).\(ext)", suffix = 2
            while used.contains(name.lowercased()) { name = "\(base)_\(suffix).\(ext)"; suffix += 1 }
            used.insert(name.lowercased())
            return name
        }
    }
    private func availableFolderName(base: String, parent: URL) throws -> String {
        // Include dangling symlinks, which must not be reused as directories.
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: parent.path).map { $0.lowercased() })
        var name = base, suffix = 2
        while existing.contains(name.lowercased()) { name = "\(base)_\(suffix)"; suffix += 1 }
        return name
    }
    public func suggestedFolderName(metadata: BatchMetadata, sessions: [Session]) throws -> String {
        try availableFolderName(base: Self.folderBaseName(metadata: metadata, sessions: sessions), parent: downloadRoot())
    }
    public func create(metadata: BatchMetadata, sessions: [Session]) throws -> Batch {
        guard !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !sessions.isEmpty else { throw SoloError.invalid("请填写批次名称并选择 session") }
        guard Set(sessions.map(\.id)).count == sessions.count else { throw SoloError.invalid("Session 选择重复") }
        let id = UUID(), now = Date()
        let bookmark = try selectedBookmark(), parent = try resolveRoot(bookmark)
        let base = Self.folderBaseName(metadata: metadata, sessions: sessions)
        var name: String
        while true {
            name = try availableFolderName(base: base, parent: parent)
            let path = parent.appendingPathComponent(name, isDirectory: true).path
            if Darwin.mkdir(path, 0o755) == 0 { break }
            let code = errno
            // Claim atomically. Never merge into someone else's existing folder.
            if code != EEXIST { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
        let files = zip(sessions, Self.fileNames(metadata: metadata, sessions: sessions)).map {
            DownloadedSession(session: $0.0, localFilename: $0.1)
        }
        let batch = Batch(id: id, createdAt: now, folderName: name, metadata: metadata, files: files, localRootBookmark: bookmark)
        try save(batch); try exportMetadata(batch)
        return batch
    }
    public func recordDownloaded(_ id: UUID, sessionID: String) throws -> Batch {
        var batch = try load(id)
        guard let i = batch.files.firstIndex(where: { $0.id == sessionID }) else { throw SoloError.invalid("批次中没有此 session") }
        let file = batch.files[i], url = try folder(batch).appendingPathComponent(file.filename)
        let digest = try FileDigest.read(url)
        guard digest.bytes == file.session.size else { throw SoloError.invalid("已保存文件大小不匹配") }
        batch.files[i].sha256 = digest.sha256; batch.files[i].md5 = digest.md5; batch.files[i].error = nil
        try save(batch); try exportMetadata(batch); return batch
    }
    public func recordError(_ id: UUID, sessionID: String, message: String) throws {
        var batch = try load(id)
        if let i = batch.files.firstIndex(where: { $0.id == sessionID }) { batch.files[i].error = message }
        try save(batch); try exportMetadata(batch)
    }
    public func verifyLocal(_ batch: Batch) throws {
        guard batch.downloadComplete else { throw SoloError.invalid("请先完成这一批的本地下载") }
        for file in batch.files {
            let digest = try FileDigest.read(folder(batch).appendingPathComponent(file.filename))
            guard digest.bytes == file.session.size, digest.sha256 == file.sha256 else { throw SoloError.invalid("本地文件校验失败：" + file.filename) }
        }
    }
    public func exportMetadata(_ batch: Batch) throws {
        // No OAuth state, account ID, or resumable upload URLs in exported metadata.
        struct Export: Encodable { let schemaVersion: Int; let batchID: UUID; let createdAt: Date; let metadata: BatchMetadata; let sessions: [DownloadedSession] }
        let renamed = batch.files.contains { $0.localFilename != nil }
        let exported = Export(schemaVersion: renamed ? 2 : 1, batchID: batch.id, createdAt: batch.createdAt, metadata: batch.metadata, sessions: batch.files)
        try encoder.encode(exported).write(to: folder(batch).appendingPathComponent("batch.json"), options: .atomic)
        var rows = [["file", "date", "time", "track", "device_laps", "device_best_lap", "duration", "bytes", "batch", "driver", "vehicle", "notes", "sha256"]]
        if renamed { rows[0].append("device_file") }
        for file in batch.files {
            let s = file.session, m = batch.metadata
            var row = [file.filename, s.dateLabel, s.time, s.track, String(s.laps), s.bestLabel, s.durationLabel, String(s.size), m.title, m.driver, m.vehicle, m.notes, file.sha256 ?? ""]
            if renamed { row.append(s.filename) }
            rows.append(row)
        }
        let csv = rows.map { $0.map(CSV.field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        try Data(csv.utf8).write(to: folder(batch).appendingPathComponent("sessions.csv"), options: .atomic)
    }
}

// Keep picker-granted access alive while files are downloaded, shared or uploaded.
// Each successful start is balanced when the store releases its cached roots.
private final class ScopedDownloadRoot: @unchecked Sendable {
    let url: URL
    private let accessed: Bool
    init(_ url: URL) { self.url = url; accessed = url.startAccessingSecurityScopedResource() }
    deinit { if accessed { url.stopAccessingSecurityScopedResource() } }
}
