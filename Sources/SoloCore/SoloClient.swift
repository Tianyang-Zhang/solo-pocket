import Foundation
import Network
import CryptoKit

private final class Completion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(with: result)
    }
}

final class SoloSocket: SoloByteStream, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "SoloPocket.socket")
    private let label: String
    private let trace: SoloTrace
    private let timeout: TimeInterval
    init(port: UInt16, udp: Bool = false, host: String = "10.0.0.1",
         timeout: TimeInterval = 8, trace: @escaping SoloTrace = { _, _ in }) {
        let parameters: NWParameters = udp ? .udp : .tcp
        // Use the working system-selected local route, without requiring a
        // Wi-Fi interface type before iOS has evaluated local-network access.
        parameters.prohibitedInterfaceTypes = [.cellular]
        label = udp ? "UDP" : "TCP"; self.trace = trace; self.timeout = timeout
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        trace("\(label).create", "host=\(host) port=\(port) route=automaticLocal prohibited=cellular")
    }
    func close() { connection.cancel() }
    private func pathSummary() -> String {
        guard let path = connection.currentPath else { return "path unavailable" }
        return Self.describe(path)
    }
    static func describe(_ path: NWPath) -> String {
        return "status=\(path.status) reason=\(path.unsatisfiedReason) wifi=\(path.usesInterfaceType(.wifi)) interfaces=\(path.availableInterfaces.map { $0.name + ":" + String(describing: $0.type) }) local=\(String(describing: path.localEndpoint)) remote=\(String(describing: path.remoteEndpoint))"
    }
    private func operation<T>(_ step: String, timeout limit: TimeInterval? = nil,
                              _ start: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let once = Completion(continuation)
                let timer = DispatchWorkItem { [weak self] in
                    guard let self else { once.finish(.failure(CancellationError())); return }
                    self.trace("\(self.label).timeout", "\(step): \(self.pathSummary())")
                    let hint = self.connection.currentPath?.unsatisfiedReason == .localNetworkDenied
                        ? "系统尚未允许本地网络访问；请检查授权弹窗或「设置 → 隐私与安全性 → 本地网络」。"
                        : "请确认 Solo Wi-Fi、本地网络权限，并关闭 LocalDevVPN。可导出连接日志定位原因。"
                    once.finish(.failure(SoloError.invalid("[\(self.label) \(step)] 超时。" + hint)))
                    self.connection.cancel()
                }
                queue.asyncAfter(deadline: .now() + (limit ?? timeout), execute: timer)
                start { [trace, label] result in
                    timer.cancel()
                    if case .failure(let error) = result, !(error is CancellationError) {
                        trace("\(label).error", "\(step): \(String(reflecting: error))")
                        once.finish(.failure(SoloError.invalid("[\(label) \(step)] " + error.localizedDescription)))
                    } else { once.finish(result) }
                }
            }
        } onCancel: { [connection] in connection.cancel() }
    }
    func connect(timeout: TimeInterval? = nil) async throws {
        let _: Void = try await operation("建立连接", timeout: timeout) { finish in
            self.connection.pathUpdateHandler = { [weak self] _ in
                guard let self else { return }; self.trace("\(self.label).path", self.pathSummary())
            }
            self.connection.stateUpdateHandler = { [weak self] state in
                if let self { self.trace("\(self.label).state", "\(state); \(self.pathSummary())") }
                switch state {
                case .ready: finish(.success(()))
                case .failed(let error): finish(.failure(error))
                case .cancelled: finish(.failure(CancellationError()))
                default: break
                }
            }
            self.connection.start(queue: self.queue)
        }
    }
    func send(_ data: Data) async throws { try await send(data, timeout: nil) }
    func send(_ data: Data, timeout: TimeInterval?) async throws {
        trace("\(label).send", "bytes=\(data.count)")
        let _: Void = try await operation("发送", timeout: timeout) { finish in
            self.connection.send(content: data, completion: .contentProcessed { error in
                if let error { finish(.failure(error)) } else { finish(.success(())) }
            })
        }
    }
    func receive(_ count: Int) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = min(count - result.count, 65536)
            let part: Data = try await operation("接收，尚需 \(count - result.count) 字节") { finish in
                self.connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
                    if let error { finish(.failure(error)) }
                    else if let data, !data.isEmpty { finish(.success(data)) }
                    else { finish(.failure(SoloError.invalid("Solo 在文件完成前断开了连接"))) }
                }
            }
            result.append(part)
        }
        trace("\(label).receive", "bytes=\(result.count)")
        return result
    }
    func datagram() async throws -> Data {
        let data: Data = try await operation("接收设备发现回应") { finish in
            self.connection.receiveMessage { data, _, _, error in
                if let error { finish(.failure(error)) }
                else if let data { finish(.success(data)) }
                else { finish(.failure(SoloError.invalid("Solo 未回应"))) }
            }
        }
        trace("\(label).datagram", "bytes=\(data.count)")
        return data
    }
}

public struct SoloClient: Sendable {
    private let trace: SoloTrace
    private let host: String
    private let transferPort: UInt16
    private let discoveryPort: UInt16
    public init(host: String = "10.0.0.1", transferPort: UInt16 = 2000, discoveryPort: UInt16 = 36002,
                trace: @escaping SoloTrace = { _, _ in }) {
        self.host = host; self.transferPort = transferPort; self.discoveryPort = discoveryPort; self.trace = trace
    }
    private func socket(port: UInt16, udp: Bool = false) -> SoloSocket {
        SoloSocket(port: port, udp: udp, host: host, trace: trace)
    }
    /// Reuse the user-validated TCP preflight automatically before discovery.
    /// Discovery is independent of owner-supplied names. SoloTransfer validates
    /// the protocol handshake before any list or download command is sent.
    public func checkLocalConnection() async throws {
        let paths = SoloPathDiagnostics(trace: trace); defer { paths.stop() }
        trace("phase", "正在连接 Solo；如出现本地网络弹窗，请点允许，随后会自动继续")
        let socket = socket(port: transferPort); defer { socket.close() }
        try await socket.connect(timeout: 25)
        trace("probe.ready", "route=automaticLocal TCP 可达；尚未验证 Solo 身份或读取 session")
    }
    public func discover() async throws {
        trace("phase", "正在发现 Solo；如出现本地网络弹窗，请点允许")
        let socket = socket(port: discoveryPort, udp: true); defer { socket.close() }
        try await socket.connect(timeout: 25); try await socket.send(Data("aim-ka".utf8), timeout: 25)
        let response = try await socket.datagram()
        // AiM discovery may include arbitrary custom names and binary fields.
        // Do not infer compatibility from a name, model label or text encoding.
        // The connected UDP socket only receives from the selected host/port;
        // the subsequent TCP handshake and framed transfer validate the protocol.
        guard !response.isEmpty else {
            throw SoloError.invalid("设备发现回应为空，请确认已连接 Solo 的 Wi-Fi")
        }
        trace("discovery.received", "收到 \(response.count) 字节回应；不限制设备名称，后续通过协议握手验证")
    }
    private func heartbeat() -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                // Keep background heartbeat events distinct from the main attempt.
                do { try await SoloClient(host: host, transferPort: transferPort, discoveryPort: discoveryPort,
                                          trace: { event, detail in trace("heartbeat." + event, detail) }).discover() }
                catch { trace("heartbeat.failed", error.localizedDescription) }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
    public func sessions() async throws -> [Session] {
        try await checkLocalConnection()
        try await discover()
        let keepAlive = heartbeat(); defer { keepAlive.cancel() }
        trace("phase", "设备已回应，正在验证 Solo 数据连接")
        let socket = socket(port: transferPort); defer { socket.close() }
        try await Task.sleep(for: .milliseconds(300)); try await socket.connect()
        var result = Data()
        try await SoloTransfer(stream: socket, trace: trace).read { data, _, _ in
            guard result.count + data.count <= SoloFrame.maxFrame else { throw SoloError.invalid("Session 列表过大") }
            result.append(data)
        }
        let sessions = try Session.parse(result)
        trace("list.parsed", "bytes=\(result.count) sessions=\(sessions.count)")
        return sessions
    }
    public func download(_ session: Session, to target: URL, progress: @escaping @Sendable (Double) async -> Void) async throws {
        try await checkLocalConnection()
        try await discover()
        let keepAlive = heartbeat(); defer { keepAlive.cancel() }
        trace("phase", "设备已回应，正在验证 Solo 下载连接")
        let socket = socket(port: transferPort); defer { socket.close() }
        let partial = target.appendingPathExtension("partial")
        let manager = FileManager.default
        guard !manager.fileExists(atPath: target.path) else { throw SoloError.invalid("目标文件已存在，未覆盖") }
        try Data().write(to: partial, options: .atomic)
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close(); try? manager.removeItem(at: partial) }
        try await Task.sleep(for: .milliseconds(300)); try await socket.connect()
        try await SoloTransfer(stream: socket, trace: trace).read(path: session.devicePath, expectedSize: session.size) { data, done, total in
            try handle.write(contentsOf: data)
            await progress(Double(done) / Double(total))
        }
        try Task.checkCancellation()
        try handle.synchronize(); try handle.close()
        try manager.moveItem(at: partial, to: target)
    }
}

public enum FileDigest {
    public static func read(_ url: URL) throws -> (bytes: Int, sha256: String, md5: String) {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha = SHA256(), md5 = Insecure.MD5(), size = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { size += data.count; sha.update(data: data); md5.update(data: data) }
        func hex<D: Sequence>(_ d: D) -> String where D.Element == UInt8 { d.map { String(format: "%02x", $0) }.joined() }
        return (size, hex(sha.finalize()), hex(md5.finalize()))
    }
}
