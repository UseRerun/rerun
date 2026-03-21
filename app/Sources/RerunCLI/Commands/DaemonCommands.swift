import ArgumentParser
import Foundation
import RerunCore

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the capture daemon."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let status = DaemonDetector.detect()
        let formatter = OutputFormatter(json: json)

        if status.running {
            if formatter.useJSON {
                try formatter.printJSON(["status": "already_running", "pid": "\(status.pid ?? 0)"])
            } else {
                print("Daemon already running (PID \(status.pid ?? 0))")
            }
            return
        }

        // Find rerun-daemon binary as sibling of this executable
        guard let execURL = Bundle.main.executableURL else {
            print("Cannot determine executable path.")
            throw ExitCode(1)
        }
        let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent("rerun-daemon")

        guard FileManager.default.fileExists(atPath: daemonURL.path) else {
            print("Daemon binary not found at \(daemonURL.path)")
            throw ExitCode(1)
        }

        let process = Process()
        process.executableURL = daemonURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .background

        do {
            try process.run()
        } catch {
            print("Failed to start daemon: \(error.localizedDescription)")
            throw ExitCode(1)
        }

        if formatter.useJSON {
            try formatter.printJSON(["status": "started", "pid": "\(process.processIdentifier)"])
        } else {
            print("Daemon started (PID \(process.processIdentifier))")
        }
    }
}

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the capture daemon."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let status = DaemonDetector.detect()
        let formatter = OutputFormatter(json: json)

        guard status.running, let pid = status.pid else {
            if formatter.useJSON {
                try formatter.printJSON(["status": "not_running"])
            } else {
                print("Daemon is not running.")
            }
            throw ExitCode(3)
        }

        kill(Int32(pid), SIGTERM)

        if formatter.useJSON {
            try formatter.printJSON(["status": "stopped", "pid": "\(pid)"])
        } else {
            print("Daemon stopped (PID \(pid))")
        }
    }
}

struct PauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause screen capture without stopping the daemon."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let pauseURL = RerunHome.pauseFileURL()
        let dir = pauseURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pauseURL.path, contents: nil)

        let formatter = OutputFormatter(json: json)
        if formatter.useJSON {
            try formatter.printJSON(["status": "paused"])
        } else {
            print("Captures paused. Use 'rerun resume' to restart.")
        }
    }
}

struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume screen capture."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let pauseURL = RerunHome.pauseFileURL()

        if FileManager.default.fileExists(atPath: pauseURL.path) {
            try FileManager.default.removeItem(at: pauseURL)
        }

        let formatter = OutputFormatter(json: json)
        if formatter.useJSON {
            try formatter.printJSON(["status": "resumed"])
        } else {
            print("Captures resumed.")
        }
    }
}
