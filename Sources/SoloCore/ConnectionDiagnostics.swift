import Foundation
import Darwin
import Network

public typealias SoloTrace = @Sendable (String, String) -> Void

/// Local-only connection metadata. Never receives telemetry payloads or OAuth data.
public final class SoloConnectionLog: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private let handle: FileHandle
    private var entries = 0
    public init(directory: URL, operation: String, appVersion: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        url = directory.appendingPathComponent("Solo-\(operation)-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).txt")
        try Data().write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
        record("start", "app=\(appVersion) os=\(ProcessInfo.processInfo.operatingSystemVersionString) target=10.0.0.1")
        record("interfaces", Self.interfaces())
    }
    deinit { try? handle.close() }
    public func record(_ event: String, _ detail: String) {
        lock.lock(); defer { lock.unlock() }
        // Bound one attempt's log even if a device sends pathological data.
        guard entries < 5000 else { return }; entries += 1
        let line = "\(Date().ISO8601Format()) [\(event)] \(detail.replacingOccurrences(of: "\n", with: " "))\n"
        try? handle.write(contentsOf: Data(line.utf8))
    }
    public static func interfaces() -> String {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return "getifaddrs failed" }
        defer { freeifaddrs(first) }
        var values: [String] = [], cursor = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard address.pointee.sa_family == UInt8(AF_INET), name != "lo0" else { continue }
            if name.hasPrefix("utun") || name.hasPrefix("pdp_ip") { values.append("\(name): IPv4 present"); continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                values.append("\(name)=\(String(cString: host))")
            }
        }
        return values.isEmpty ? "No non-loopback IPv4 address" : values.sorted().joined(separator: "; ")
    }
}

/// Observes available paths without sending packets or gating an attempt.
final class SoloPathDiagnostics {
    private let monitors = [NWPathMonitor(), NWPathMonitor(requiredInterfaceType: .wifi)]
    init(trace: @escaping SoloTrace) {
        let queue = DispatchQueue(label: "SoloPocket.pathDiagnostics")
        for (name, monitor) in zip(["system", "wifi"], monitors) {
            monitor.pathUpdateHandler = { path in trace("monitor." + name, SoloSocket.describe(path)) }
            monitor.start(queue: queue)
        }
    }
    func stop() { monitors.forEach { $0.cancel() } }
    deinit { stop() }
}
