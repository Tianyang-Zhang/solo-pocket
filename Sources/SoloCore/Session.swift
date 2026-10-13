import Foundation

public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: String { devicePath }
    public let filename: String
    public let date: String
    public let time: String
    public let track: String
    public let laps: Int
    public let bestMilliseconds: Int?
    public let durationMilliseconds: Int
    public let size: Int
    public var hasBestLap: Bool { (bestMilliseconds ?? 0) > 0 }
    public var devicePath: String { "1:/mem/" + filename }
    public var dateLabel: String {
        let parts = date.split(separator: "/")
        return parts.count == 3 ? "\(parts[2])-\(parts[1])-\(parts[0])" : date
    }
    public var bestLabel: String {
        guard let ms = bestMilliseconds, ms > 0 else { return "—" }
        return String(format: "%d:%02d.%03d", ms / 60000, (ms / 1000) % 60, ms % 1000)
    }
    public var durationLabel: String {
        String(format: "%d:%02d", durationMilliseconds / 60000, (durationMilliseconds / 1000) % 60)
    }
    public var title: String { "\(dateLabel)  \(time)" }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    public static func validPath(_ path: String) -> Bool {
        path.utf8.count <= 31 && path.range(of: #"^1:/mem/[A-Za-z0-9_-]+\.(xrz|xrk)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    public static func parse(_ data: Data) throws -> [Session] {
        guard let text = String(data: data, encoding: .utf8) else { throw SoloError.invalid("设备列表不是 UTF-8 文本") }
        let rows = try CSV.rows(text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\0", with: ""))
        guard let header = rows.first, Set(["name", "size", "date", "hour"]).isSubset(of: Set(header)) else {
            throw SoloError.invalid("设备列表格式尚未识别")
        }
        var result: [Session] = [], seen = Set<String>()
        for row in rows.dropFirst() {
            func value(_ key: String) -> String { guard let i = header.firstIndex(of: key), i < row.count else { return "" }; return row[i] }
            let rawName = value("name")
            let name = rawName.hasPrefix("1:/mem/") ? String(rawName.dropFirst(7)) : rawName
            guard validPath("1:/mem/" + name), let size = Int(value("size")), size > 0, size <= SoloFrame.maxFile,
                  seen.insert(name).inserted else { continue }
            result.append(Session(filename: name, date: value("date"), time: value("hour"), track: value("track_name"),
                                  laps: max(0, Int(value("nlap")) ?? 0), bestMilliseconds: Int(value("best")),
                                  durationMilliseconds: max(0, Int(value("test_dur")) ?? 0), size: size))
        }
        return result
    }
}

public enum SoloError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}

public enum CSV {
    public static func rows(_ text: String) throws -> [[String]] {
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r" || c == "\r\n") && !quoted {
                row.append(field); if row.contains(where: { !$0.isEmpty }) { result.append(row) }; row = []; field = ""
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw SoloError.invalid("CSV 引号不完整") }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        return result
    }
    public static func field(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
