import SwiftUI
import SoloCore

@MainActor final class AppModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var selected = Set<String>()
    @Published var batches: [Batch] = []
    @Published var busy = false
    @Published var status = "连接 Solo 的 Wi-Fi 后，读取 session 列表。"
    @Published var progress = 0.0
    @Published var error: String?
    @Published var tab = 0
    @Published var downloadRootLabel = "我的 iPhone → Solo Pocket → Solo Sessions"
    @Published var usesDefaultDownloadRoot = true
    @Published var diagnosticURL: URL?
    @Published var lastConnectionError: String?
    @Published var hideSessionsWithoutBestLap = UserDefaults.standard.object(forKey: "hideSessionsWithoutBestLap") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hideSessionsWithoutBestLap, forKey: "hideSessionsWithoutBestLap")
            selected.formIntersection(Set(visibleSessions.map(\.id)))
        }
    }
    let store: BatchStore
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    private var operation: Task<Void, Never>?
    private var activeDiagnostic: SoloConnectionLog?
    var visibleSessions: [Session] { hideSessionsWithoutBestLap ? sessions.filter(\.hasBestLap) : sessions }
    var selectedSessions: [Session] { visibleSessions.filter { selected.contains($0.id) } }
    var localSessionKeys: Set<String> { Set(batches.flatMap(\.files).filter(\.downloaded).map { Self.key($0.session) }) }
    static func key(_ s: Session) -> String { "\(s.filename)|\(s.date)|\(s.time)|\(s.size)" }
    init() {
        let fm = FileManager.default
        do {
            let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            store = try BatchStore(root: documents.appendingPathComponent("Solo Sessions", isDirectory: true), stateRoot: support.appendingPathComponent("SoloState", isDirectory: true))
        } catch { fatalError("无法创建本地存储：\(error.localizedDescription)") }
        Task { await reload(); await refreshDownloadRoot() }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logs = (try? fm.contentsOfDirectory(at: documents.appendingPathComponent("Solo Diagnostics"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            diagnosticURL = logs.filter { $0.pathExtension == "txt" }.max {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
        }
        if demo, let url = Bundle.main.url(forResource: "sessions", withExtension: "csv") {
            do { sessions = try Session.parse(Data(contentsOf: url)); status = "演示模式 · 使用已验证的设备列表，不连接 Solo" }
            catch { self.error = error.localizedDescription }
        }
    }
    func reload() async { do { batches = try await store.list() } catch { self.error = "本地批次读取失败：" + error.localizedDescription } }
    func refreshDownloadRoot() async {
        do {
            usesDefaultDownloadRoot = try await store.usesDefaultDownloadRoot()
            let url = try await store.downloadRoot()
            downloadRootLabel = Self.folderLabel(url)
        } catch { downloadRootLabel = "原目录无法访问，请重新选择"; self.error = error.localizedDescription }
    }
    static func folderLabel(_ url: URL) -> String {
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let base = documents.standardizedFileURL.path, path = url.standardizedFileURL.path
            if path == base { return "我的 iPhone → Solo Pocket" }
            if path.hasPrefix(base + "/") { return "我的 iPhone → Solo Pocket → " + path.dropFirst(base.count + 1).replacingOccurrences(of: "/", with: " → ") }
        }
        return "自选文件夹：" + url.lastPathComponent
    }
    func changeDownloadRoot(_ url: URL?) {
        guard !busy else { return }
        Task {
            do { try await store.setDownloadRoot(url); await refreshDownloadRoot() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; progress = 0; error = nil; activeDiagnostic = nil; UIApplication.shared.isIdleTimerDisabled = true
        operation = Task {
            defer { busy = false; operation = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await work(); activeDiagnostic?.record("operation.success", status) }
            catch {
                activeDiagnostic?.record("operation.failed", String(reflecting: error))
                if activeDiagnostic != nil, !(error is CancellationError), !Task.isCancelled { lastConnectionError = error.localizedDescription }
                if Task.isCancelled || error is CancellationError { status = "已暂停。完成的文件已保留，可以继续。" }
                else { self.error = error.localizedDescription; status = "未完成，本地文件已保留。" }
            }
            await reload()
        }
    }
    private func beginConnectionLog(_ operation: String) throws -> SoloTrace {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let log = try SoloConnectionLog(directory: documents.appendingPathComponent("Solo Diagnostics"), operation: operation, appVersion: version)
        log.record("app.configuration", "bundle=\(Bundle.main.bundleIdentifier ?? "unknown") localNetworkDescriptionPresent=\(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") != nil)")
        log.record("app.connectionRoute", "automaticLocal")
        activeDiagnostic = log; diagnosticURL = log.url; lastConnectionError = nil
        return { [weak self] event, detail in
            log.record(event, detail)
            if event == "phase" { Task { @MainActor in if self?.busy == true { self?.status = detail } } }
        }
    }
    func checkLocalConnection() {
        guard !demo else { return }
        run {
            let trace = try self.beginConnectionLog("probe")
            try await SoloClient(trace: trace).checkLocalConnection()
            self.status = "本地连接已连通。回到 Solo 页即可读取列表。"
        }
    }
    func scan() {
        guard !demo else { return }
        run {
            self.status = "正在连接 Solo 2 Tom…"
            let trace = try self.beginConnectionLog("scan")
            self.sessions = try await SoloClient(trace: trace).sessions()
            self.selected = self.selected.intersection(Set(self.visibleSessions.map(\.id)))
            self.status = "已读取 \(self.sessions.count) 个 session，请选择要下载的记录。"
        }
    }
    func startDownload(_ metadata: BatchMetadata) {
        let selection = selectedSessions
        guard !demo, !selection.isEmpty else { return }
        run {
            let batch = try await self.store.create(metadata: metadata, sessions: selection)
            UserDefaults.standard.set(metadata.driver, forKey: "lastDriver")
            UserDefaults.standard.set(metadata.vehicle, forKey: "lastVehicle")
            self.selected.removeAll(); self.tab = 1; await self.reload()
            try await self.download(batch)
        }
    }
    func resume(_ batch: Batch) { run { try await self.download(try await self.store.load(batch.id)) } }
    private func download(_ batch: Batch) async throws {
        let trace = try beginConnectionLog("download")
        let client = SoloClient(trace: trace), folder = try await store.folder(batch)
        for (index, file) in batch.files.enumerated() {
            try Task.checkCancellation()
            if file.downloaded { continue }
            let session = file.session, target = folder.appendingPathComponent(file.filename)
            status = "下载 \(index + 1)/\(batch.files.count) · \(session.time)"
            do {
                // Recover a file atomically renamed just before an app termination.
                if !FileManager.default.fileExists(atPath: target.path) {
                    try await client.download(session, to: target) { fraction in
                        await MainActor.run { self.progress = (Double(index) + fraction) / Double(batch.files.count) }
                    }
                }
                _ = try await store.recordDownloaded(batch.id, sessionID: file.id)
                await reload()
            } catch {
                try? await store.recordError(batch.id, sessionID: file.id, message: Task.isCancelled ? "已暂停，等待继续" : error.localizedDescription)
                throw error
            }
        }
        progress = 1; status = "这一批已保存到手机。恢复网络后，可以选择上传 Google Drive。"
    }
    func upload(_ batch: Batch, account: GoogleAccount) {
        guard !account.folderID.isEmpty, !account.accountID.isEmpty else { error = "请先在设置中登录 Google Drive，并选好上传文件夹。"; return }
        let accountID = account.accountID, parent = account.folderID, drive = account.client()
        run {
            self.status = "正在检查本地文件并上传…"
            try await BatchUploader(drive: drive, store: self.store).upload(id: batch.id, accountID: accountID, parentID: parent) { _, fraction in
                await MainActor.run { self.progress = fraction; self.status = "正在上传 \(batch.metadata.title) · \(Int(fraction * 100))%" }
            }
            self.progress = 1; self.status = "整批已上传到 Google Drive，本地原文件继续保留。"
        }
    }
    func pause() { operation?.cancel() }
}
