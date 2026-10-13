import Foundation

public struct DriveFile: Codable, Sendable {
    public let id: String
    public let name: String?
    public let mimeType: String?
    public let size: String?
    public let md5Checksum: String?
    public let parents: [String]?
    public let trashed: Bool?
}
public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]
    public init(data: Data, status: Int, headers: [String: String] = [:]) {
        self.data = data; self.status = status; self.headers = headers
    }
    public func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
}
public struct DriveClient: Sendable {
    public typealias HTTP = @Sendable (URLRequest) async throws -> HTTPResult
    private let token: @Sendable () async throws -> String
    private let http: HTTP
    public init(token: @escaping @Sendable () async throws -> String, http: @escaping HTTP = { try await DriveClient.liveHTTP($0) }) {
        self.token = token; self.http = http
    }
    public static func liveHTTP(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SoloError.invalid("Google Drive 回应无效") }
        return HTTPResult(data: data, status: response.statusCode, headers: response.allHeaderFields.reduce(into: [:]) { $0[String(describing: $1.key)] = String(describing: $1.value) })
    }
    private func request(_ url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) async throws -> HTTPResult {
        guard url.scheme == "https", url.host == "www.googleapis.com" else { throw SoloError.invalid("Google Drive 上传地址无效") }
        try Task.checkCancellation()
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 45
        request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await http(request)
    }
    private func checked(_ result: HTTPResult) throws -> Data {
        guard (200..<300).contains(result.status) else {
            let message: String
            switch result.status {
            case 401: message = "Google 登录已失效，请重新登录"
            case 403: message = "Google Drive 无权访问、空间或配额不足，请检查账号和文件夹"
            case 404: message = "Google Drive 目标不存在或未授权"
            default: message = "Google Drive 请求未完成（\(result.status)），本地文件已保留，可重试"
            }
            throw SoloError.invalid(message)
        }
        return result.data
    }
    public func generateID() async throws -> String {
        let data = try checked(await request(URL(string: "https://www.googleapis.com/drive/v3/files/generateIds?count=1&space=drive&type=files")!))
        struct IDs: Decodable { let ids: [String] }
        guard let id = try JSONDecoder().decode(IDs.self, from: data).ids.first else { throw SoloError.invalid("未取得 Drive 文件编号") }
        return id
    }
    public func file(_ id: String) async throws -> DriveFile? {
        guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { throw SoloError.invalid("Drive 文件编号无效") }
        let result = try await request(URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?fields=id,name,mimeType,size,md5Checksum,parents,trashed")!)
        if result.status == 404 { return nil }
        return try JSONDecoder().decode(DriveFile.self, from: checked(result))
    }
    public func ensureFolder(id: String, name: String, parent: String?) async throws {
        if let existing = try await file(id) {
            guard existing.mimeType == "application/vnd.google-apps.folder", existing.trashed != true,
                  parent == nil || existing.parents?.contains(parent!) == true else { throw SoloError.invalid("Drive 批次文件夹位置已改变，请检查目标") }
            return
        }
        var metadata: [String: Any] = ["id": id, "name": name, "mimeType": "application/vnd.google-apps.folder", "appProperties": ["soloPocket": "folder"]]
        if let parent { metadata["parents"] = [parent] }
        let result = try await request(URL(string: "https://www.googleapis.com/drive/v3/files")!, method: "POST", body: JSONSerialization.data(withJSONObject: metadata), headers: ["Content-Type": "application/json"])
        if result.status == 409 {
            guard let remote = try await file(id), remote.mimeType == "application/vnd.google-apps.folder", remote.trashed != true,
                  parent == nil || remote.parents?.contains(parent!) == true else { throw SoloError.invalid("Drive 文件夹重试校验失败") }
        } else { _ = try checked(result) }
    }
    public func folders() async throws -> [DriveFile] {
        var all: [DriveFile] = [], page: String?
        repeat {
            var parts = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            parts.queryItems = [URLQueryItem(name: "q", value: "mimeType = 'application/vnd.google-apps.folder' and trashed = false"), URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType)"), URLQueryItem(name: "pageSize", value: "100")]
            if let page { parts.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
            let data = try checked(await request(parts.url!))
            struct Page: Decodable { let files: [DriveFile]; let nextPageToken: String? }
            let decoded = try JSONDecoder().decode(Page.self, from: data); all += decoded.files; page = decoded.nextPageToken
        } while page != nil
        return all
    }
    public static func resumeOffset(_ header: String?, size: Int) throws -> Int {
        guard let header else { return 0 }
        guard header.hasPrefix("bytes=0-"), let last = Int(header.dropFirst(8)), last >= 0, last < size else { throw SoloError.invalid("Drive 续传位置无效") }
        return last + 1
    }
    private func matches(_ remote: DriveFile, bytes: Int, md5: String, parent: String) -> Bool {
        remote.trashed != true && remote.size == String(bytes) && remote.md5Checksum?.lowercased() == md5.lowercased() && remote.parents?.contains(parent) == true
    }
    public func upload(url: URL, parent: String, receipt: UploadReceipt,
                       checkpoint: (UploadReceipt) async throws -> Void,
                       progress: (Double) async -> Void) async throws -> UploadReceipt {
        let digest = try FileDigest.read(url)
        guard digest.bytes > 0 else { throw SoloError.invalid("不能上传空文件") }
        var state = receipt
        if let remote = try await file(state.fileID) {
            guard matches(remote, bytes: digest.bytes, md5: digest.md5, parent: parent) else { throw SoloError.invalid("云端已有同编号文件，但校验不匹配；本地原文件已保留") }
            state.complete = true; state.resumableURL = nil; try await checkpoint(state); return state
        }
        var offset = 0
        if let resume = state.resumableURL {
            let result = try await request(resume, method: "PUT", body: Data(), headers: ["Content-Length": "0", "Content-Range": "bytes */\(digest.bytes)"])
            if result.status == 308 { offset = try Self.resumeOffset(result.header("Range"), size: digest.bytes) }
            else if result.status == 404 || result.status == 410 { state.resumableURL = nil; try await checkpoint(state) }
            else if result.status == 200 || result.status == 201 { return try await finish(state, digest: digest, parent: parent, checkpoint: checkpoint) }
            else { _ = try checked(result) }
        }
        if state.resumableURL == nil {
            let metadata: [String: Any] = ["id": state.fileID, "name": url.lastPathComponent, "parents": [parent], "appProperties": ["soloSHA256": digest.sha256]]
            let result = try await request(URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!, method: "POST", body: JSONSerialization.data(withJSONObject: metadata), headers: ["Content-Type": "application/json", "X-Upload-Content-Type": "application/octet-stream", "X-Upload-Content-Length": String(digest.bytes)])
            if result.status == 409 { return try await finish(state, digest: digest, parent: parent, checkpoint: checkpoint) }
            _ = try checked(result)
            guard let location = result.header("Location"), let upload = URL(string: location), upload.scheme == "https", upload.host == "www.googleapis.com" else { throw SoloError.invalid("Drive 未返回有效上传地址") }
            state.resumableURL = upload; try await checkpoint(state)
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        while offset < digest.bytes {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let length = min(1024 * 1024, digest.bytes - offset)
            guard let chunk = try handle.read(upToCount: length), chunk.count == length else { throw SoloError.invalid("本地文件在上传时发生变化") }
            let result = try await request(state.resumableURL!, method: "PUT", body: chunk, headers: ["Content-Type": "application/octet-stream", "Content-Length": String(length), "Content-Range": "bytes \(offset)-\(offset + length - 1)/\(digest.bytes)"])
            if result.status == 200 || result.status == 201 { return try await finish(state, digest: digest, parent: parent, checkpoint: checkpoint) }
            guard result.status == 308 else { _ = try checked(result); throw SoloError.invalid("Drive 上传回应异常") }
            let next = try Self.resumeOffset(result.header("Range"), size: digest.bytes)
            guard next > offset, next <= offset + length else { throw SoloError.invalid("Drive 上传未取得进展，请重试") }
            offset = next; await progress(Double(offset) / Double(digest.bytes))
        }
        return try await finish(state, digest: digest, parent: parent, checkpoint: checkpoint)
    }
    private func finish(_ receipt: UploadReceipt, digest: (bytes: Int, sha256: String, md5: String), parent: String,
                        checkpoint: (UploadReceipt) async throws -> Void) async throws -> UploadReceipt {
        guard let remote = try await file(receipt.fileID), matches(remote, bytes: digest.bytes, md5: digest.md5, parent: parent) else { throw SoloError.invalid("Drive 上传后校验未通过，请保留本地文件并重试") }
        var state = receipt; state.complete = true; state.resumableURL = nil; try await checkpoint(state); return state
    }
}

public struct BatchUploader: Sendable {
    public let drive: DriveClient
    public let store: BatchStore
    public init(drive: DriveClient, store: BatchStore) { self.drive = drive; self.store = store }
    public func upload(id: UUID, accountID: String, parentID: String, progress: (String, Double) async -> Void) async throws {
        var batch = try await store.load(id)
        try await store.verifyLocal(batch)
        if let account = batch.driveAccountID, account != accountID { throw SoloError.invalid("此批次已绑定另一个 Google 账号，请切回原账号上传") }
        if let parent = batch.driveParentID, parent != parentID { throw SoloError.invalid("此批次已绑定原上传文件夹，请在设置中选择原文件夹") }
        batch.driveAccountID = accountID; batch.driveParentID = parentID
        if batch.driveFolderID == nil { batch.driveFolderID = try await drive.generateID() }
        try await store.save(batch)
        try await drive.ensureFolder(id: batch.driveFolderID!, name: batch.folderName, parent: parentID)
        try await store.exportMetadata(batch)
        let folder = try await store.folder(batch), parent = batch.driveFolderID!
        let names = batch.files.map(\.filename) + ["batch.json", "sessions.csv"]
        for (index, name) in names.enumerated() {
            try Task.checkCancellation()
            batch = try await store.load(id)
            if batch.uploads[name] == nil { batch.uploads[name] = UploadReceipt(fileID: try await drive.generateID()); try await store.save(batch) }
            let receipt = batch.uploads[name]!
            _ = try await drive.upload(url: folder.appendingPathComponent(name), parent: parent, receipt: receipt) { updated in
                var latest = try await store.load(id); latest.uploads[name] = updated; try await store.save(latest)
            } progress: { fraction in await progress(name, (Double(index) + fraction) / Double(names.count)) }
            await progress(name, Double(index + 1) / Double(names.count))
        }
        batch = try await store.load(id); batch.uploadedAt = Date(); try await store.save(batch)
    }
}
