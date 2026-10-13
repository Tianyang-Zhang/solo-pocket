import Foundation

public enum SoloFrame {
    public static let maxFrame = 1024 * 1024
    public static let maxFile = 128 * 1024 * 1024
    public static let handshake = Data([0, 0, 0, 0, 6, 8, 0, 0])
    public static func little(_ n: Int, bytes: Int = 4) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
    public static func number(_ data: Data, at offset: Int, bytes: Int = 4) throws -> Int {
        guard offset >= 0, offset + bytes <= data.count else { throw SoloError.invalid("数据字段不完整") }
        return (0..<bytes).reduce(0) { $0 | (Int(data[data.startIndex + offset + $1]) << ($1 * 8)) }
    }
    public static func encode(tag: String = "STCP", payload: Data) throws -> Data {
        guard tag.utf8.count == 4, payload.count <= maxFrame else { throw SoloError.invalid("数据帧过大") }
        let sum = payload.reduce(0) { ($0 + Int($1)) & 65535 }
        return Data("<h\(tag)".utf8) + little(payload.count) + Data([0, 62]) + payload + Data("<\(tag)".utf8) + little(sum, bytes: 2) + Data([62])
    }
    public static func decode(_ data: Data) throws -> Data {
        guard data.count >= 20, data.prefix(2) == Data("<h".utf8), data.subdata(in: 10..<12) == Data([0, 62]) else { throw SoloError.invalid("Solo 数据帧头无效") }
        let size = try number(data, at: 6)
        guard size <= maxFrame, data.count == size + 20 else { throw SoloError.invalid("Solo 数据帧长度无效") }
        let tag = data.subdata(in: 2..<6), payload = data.subdata(in: 12..<(12 + size))
        let tail = Data(data.suffix(8))
        guard tail.prefix(5) == Data([60]) + tag, tail.last == 62,
              try number(tail, at: 5, bytes: 2) == payload.reduce(0, { ($0 + Int($1)) & 65535 }) else { throw SoloError.invalid("Solo 数据校验失败") }
        return payload
    }
    public static func command(path: String? = nil) throws -> Data {
        var command = Data(repeating: 0, count: 64)
        command[8] = path == nil ? 36 : 2; command[10] = path == nil ? 2 : 4; command[24] = 1
        if let path {
            guard Session.validPath(path) else { throw SoloError.invalid("无效的 session 路径") }
            command.replaceSubrange(32..<(32 + path.utf8.count), with: path.utf8)
        }
        return command
    }
}

public protocol SoloByteStream: Sendable {
    func send(_ data: Data) async throws
    func receive(_ count: Int) async throws -> Data
}

public struct SoloTransfer: Sendable {
    let stream: any SoloByteStream
    let trace: SoloTrace
    public init(stream: any SoloByteStream, trace: @escaping SoloTrace = { _, _ in }) { self.stream = stream; self.trace = trace }
    private func frame() async throws -> Data {
        let header = try await stream.receive(12)
        guard header.count == 12, header.prefix(2) == Data("<h".utf8), header.suffix(2) == Data([0, 62]) else { throw SoloError.invalid("Solo 帧头无效") }
        let size = try SoloFrame.number(header, at: 6)
        guard size <= SoloFrame.maxFrame else { throw SoloError.invalid("Solo 数据帧超限") }
        return try SoloFrame.decode(header + (try await stream.receive(size + 8)))
    }
    public func read(path: String? = nil, expectedSize: Int? = nil,
                     chunk: (Data, Int, Int) async throws -> Void) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        trace("phase", "正在发送 Solo 连接握手")
        try await stream.send(SoloFrame.encode(payload: SoloFrame.handshake))
        trace("phase", "等待 Solo 握手回应")
        let reply = try await frame()
        guard reply == Data([0, 0, 0, 0, 6, 9, 0, 0]) else { throw SoloError.invalid("Solo 连接回应与已验证版本不一致") }
        trace("handshake.accepted", "已收到预期的 8 字节回应")
        trace("phase", path == nil ? "正在请求 session 列表" : "正在请求所选记录")
        try await stream.send(SoloFrame.encode(tag: "STNC", payload: SoloFrame.command(path: path)))
        func response() async throws -> Data {
            for _ in 0..<12 {
                let data = try await frame()
                guard data.count == 64 else { throw SoloError.invalid("Solo 命令回应长度无效") }
                if data[24] != 0x25 { return data }
                try await Task.sleep(for: .milliseconds(150))
            }
            throw SoloError.invalid("Solo 正在忙，请退出 AimMac 后重试")
        }
        _ = try await response(); trace("command.ack", "收到首个命令回应")
        let header = try await response(), total = try SoloFrame.number(header, at: 16)
        trace("transfer.size", "bytes=\(total)")
        guard total <= SoloFrame.maxFile, expectedSize == nil || total == expectedSize else { throw SoloError.invalid("文件大小与 session 列表不一致，请重新读取列表") }
        var offset = 0
        while offset < total {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw SoloError.invalid("传输超过三分钟，请重试") }
            try await stream.send(SoloFrame.encode(payload: SoloFrame.little(offset)))
            let data = try await frame()
            guard data.count > 4, try SoloFrame.number(data, at: 0) == offset, offset + data.count - 4 <= total else { throw SoloError.invalid("文件数据块位置或长度不一致") }
            let payload = Data(data.dropFirst(4)); offset += payload.count
            try await chunk(payload, offset, total)
        }
    }
}
