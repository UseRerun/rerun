import ArgumentParser
import Foundation
import RerunCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Rerun daemon status and capture statistics.",
        discussion: """
            Examples:
              rerun status            Show status in terminal
              rerun status --json     Output as JSON
              rerun status | jq .     Pipe-friendly (auto-JSON)
            """
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        let profile = RerunProfile.current()
        let formatter = OutputFormatter(json: json, noColor: noColor)

        let db = try DatabaseManager(path: DatabaseManager.defaultPath(profile: profile))
        let stats = try await StatsProvider.gatherStats(db: db, profile: profile)

        if formatter.useJSON {
            try formatter.printJSON(stats)
        } else {
            printHuman(stats)
        }

        if !stats.daemonRunning {
            throw ExitCode(3)
        }
    }

    private func printHuman(_ stats: RerunStats) {
        var lines: [String] = []
        lines.append("Rerun v\(stats.version)")
        lines.append("Profile: \(stats.profile)")

        if stats.daemonRunning, let pid = stats.daemonPID {
            lines.append("Status: running (PID \(pid))")
        } else {
            lines.append("Status: not running")
        }

        lines.append("Captures: \(formatNumber(stats.totalCaptures))")

        if let oldest = formatDate(stats.oldestCapture),
           let newest = formatDate(stats.newestCapture) {
            if oldest == newest {
                lines.append("Date range: \(oldest)")
            } else {
                lines.append("Date range: \(oldest) to \(newest)")
            }
        }

        let totalBytes = stats.databaseSizeBytes + stats.capturesSizeBytes
        if totalBytes > 0 {
            lines.append("Storage: \(formatBytes(totalBytes))")
        }

        for line in lines {
            print(line)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDate(_ iso8601: String?) -> String? {
        guard let iso = iso8601 else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: iso) else {
            // Try without fractional seconds
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            guard let date = df.date(from: iso) else {
                return String(iso.prefix(10))
            }
            let out = DateFormatter()
            out.dateFormat = "yyyy-MM-dd"
            return out.string(from: date)
        }
        let out = DateFormatter()
        out.dateFormat = "yyyy-MM-dd"
        return out.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
