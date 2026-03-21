import Foundation

public struct DaemonDetector: Sendable {
    public struct DaemonStatus: Sendable, Equatable {
        public let running: Bool
        public let pid: Int?

        public init(running: Bool, pid: Int?) {
            self.running = running
            self.pid = pid
        }
    }

    public static func detect(profile: String = RerunProfile.current()) -> DaemonStatus {
        let expectedProcessNames = expectedProcessNames(profile: profile)
        return detect(
            pidFileURL: RerunHome.pidFileURL(profile: profile),
            expectedProcessNames: expectedProcessNames
        ) {
            detectViaPgrep(expectedProcessNames: expectedProcessNames, profile: profile)
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

    static func commandLine(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "command="]

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
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? nil : output
    }

    static func commandLine(_ commandLine: String, matchesProfile profile: String) -> Bool {
        let profile = RerunProfile.normalized(profile)

        if let explicitProfile = explicitProfile(fromCommandLine: commandLine) {
            return explicitProfile == profile
        }

        let inferredProfile = RerunAppVariant.allCases.first(where: { variant in
            commandLine.contains("/\(variant.appName).app/Contents/MacOS/\(variant.executableName)") ||
            commandLine.hasSuffix("/\(variant.executableName)") ||
            commandLine == variant.executableName
        })?.profile ?? RerunProfile.defaultName

        return inferredProfile == profile
    }

    private static func detectViaPgrep(expectedProcessName: String, profile: String) -> DaemonStatus {
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

        for line in output.split(separator: "\n") {
            guard let pid = Int(line) else { continue }
            guard let processCommandLine = commandLine(for: pid) else { continue }
            if commandLine(processCommandLine, matchesProfile: profile) {
                return DaemonStatus(running: true, pid: pid)
            }
        }

        return DaemonStatus(running: false, pid: nil)
    }

    private static func detectViaPgrep(expectedProcessNames: [String], profile: String) -> DaemonStatus {
        for expectedProcessName in expectedProcessNames {
            let status = detectViaPgrep(expectedProcessName: expectedProcessName, profile: profile)
            if status.running {
                return status
            }
        }

        return DaemonStatus(running: false, pid: nil)
    }

    private static func expectedProcessNames(profile: String) -> [String] {
        var names = ["rerun-daemon"]
        if let variant = RerunAppVariant.variant(forProfile: profile) {
            names.insert(variant.executableName, at: 0)
        }
        return names
    }

    private static func explicitProfile(fromCommandLine commandLine: String) -> String? {
        let parts = commandLine.split(separator: " ").map(String.init)
        for (index, part) in parts.enumerated() {
            if part == "--profile", index + 1 < parts.count {
                return RerunProfile.normalized(parts[index + 1])
            }
            if part.hasPrefix("--profile=") {
                return RerunProfile.normalized(String(part.dropFirst("--profile=".count)))
            }
        }
        return nil
    }
}
