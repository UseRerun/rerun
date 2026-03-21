import Foundation

public struct DaemonDetector: Sendable {
    public struct DaemonStatus: Sendable {
        public let running: Bool
        public let pid: Int?
    }

    public static func detect() -> DaemonStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "rerun-daemon"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return DaemonStatus(running: false, pid: nil)
        }

        guard process.terminationStatus == 0 else {
            return DaemonStatus(running: false, pid: nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // pgrep may return multiple PIDs (one per line), take the first
        if let firstLine = output.split(separator: "\n").first, let pid = Int(firstLine) {
            return DaemonStatus(running: true, pid: pid)
        }

        return DaemonStatus(running: false, pid: nil)
    }
}
