import Foundation

public struct MarkdownWriter: Sendable {
    private let baseURL: URL

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? RerunHome.baseURL()
    }

    /// Writes a Capture as a Markdown file with YAML frontmatter.
    /// Returns the relative path from baseURL (e.g. "captures/2026/03/21/14-32-15.md").
    public func write(_ capture: Capture) throws -> String {
        let date = parseTimestamp(capture.timestamp)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // Directory: captures/YYYY/MM/DD/
        dateFormatter.dateFormat = "yyyy"
        let year = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "MM"
        let month = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "dd"
        let day = dateFormatter.string(from: date)

        let dirURL = baseURL
            .appendingPathComponent("captures", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)

        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // Filename: HH-mm-ss.md with collision handling
        dateFormatter.dateFormat = "HH-mm-ss"
        let baseName = dateFormatter.string(from: date)

        var filename = "\(baseName).md"
        var suffix = 2
        while FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(filename).path) {
            filename = "\(baseName)-\(suffix).md"
            suffix += 1
        }

        // Render markdown
        var md = "---\n"
        md += "id: \(capture.id)\n"
        md += "timestamp: \(capture.timestamp)\n"
        md += "app: \(capture.appName)\n"
        if let bundleId = capture.bundleId {
            md += "bundle_id: \(bundleId)\n"
        }
        if let windowTitle = capture.windowTitle {
            let escaped = windowTitle.replacingOccurrences(of: "\"", with: "\\\"")
            md += "window: \"\(escaped)\"\n"
        }
        if let url = capture.url {
            md += "url: \(url)\n"
        }
        md += "source: \(capture.textSource)\n"
        md += "trigger: \(capture.captureTrigger)\n"
        md += "---\n\n"
        md += capture.textContent
        md += "\n"

        let fileURL = dirURL.appendingPathComponent(filename)
        try md.write(to: fileURL, atomically: true, encoding: .utf8)

        // Return relative path from baseURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        return String(fileURL.path.dropFirst(basePath.count))
    }

    private func parseTimestamp(_ timestamp: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: timestamp) ?? Date()
    }
}
