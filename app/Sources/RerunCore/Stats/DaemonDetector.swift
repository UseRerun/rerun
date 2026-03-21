import Foundation

public struct DaemonDetector: Sendable {
    private static let expectedProcessNames = ["Rerun", "rerun-daemon"]

    public struct DaemonStatus: Sendable, Equatable {
        public let running: Bool
        public let pid: Int?

        public init(running: Bool, pid: Int?) {
            self.running = running
            self.pid = pid
        }
    }

    public static func detect() -> DaemonStatus {
        detect(
            pidFileURL: RerunHome.pidFileURL(),
            expectedProcessNames: expectedProcessNames
        ) {
            detectViaPgrep(expectedProcessNames: expectedProcessNames)
        }
    }

    static func detect(
        pidFileURL: URL,
        expectedProcessNames: [String],
        fallback: () -> DaemonStatus
    ) -> DaemonStatus {
        // Try PID file first
        if let pidString = try? String(contentsOf: pidFileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int(pidString) {
            guard kill(Int32(pid), 0) == 0 else {
                try? FileManager.default.removeItem(at: pidFileURL)
                return fallback()
            }

            if let processName = commandName(for: pid),
               expectedProcessNames.contains(processName) {
                return DaemonStatus(running: true, pid: pid)
            }

            try? FileManager.default.removeItem(at: pidFileURL)
        }

        return fallback()
    }

    static func detect(
        pidFileURL: URL,
        expectedProcessName: String,
        fallback: () -> DaemonStatus
    ) -> DaemonStatus {
        detect(
            pidFileURL: pidFileURL,
            expectedProcessNames: [expectedProcessName],
            fallback: fallback
        )
    }

    static func commandName(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "comm="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: output).lastPathComponent
    }

    private static func detectViaPgrep(expectedProcessName: String) -> DaemonStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", expectedProcessName]

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

        if let firstLine = output.split(separator: "\n").first, let pid = Int(firstLine) {
            return DaemonStatus(running: true, pid: pid)
        }

        return DaemonStatus(running: false, pid: nil)
    }

    private static func detectViaPgrep(expectedProcessNames: [String]) -> DaemonStatus {
        for expectedProcessName in expectedProcessNames {
            let status = detectViaPgrep(expectedProcessName: expectedProcessName)
            if status.running {
                return status
            }
        }

        return DaemonStatus(running: false, pid: nil)
    }
}
