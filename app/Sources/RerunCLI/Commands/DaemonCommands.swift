import ArgumentParser
import AppKit
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
        if LaunchAgentManager.isInstalled() {
            do {
                try LaunchAgentManager.uninstall()
            } catch {
                print("Failed to remove legacy LaunchAgent: \(error)")
                throw ExitCode(1)
            }
        }

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

        guard let execURL = Bundle.main.executableURL else {
            print("Cannot determine executable path.")
            throw ExitCode(1)
        }

        // Try to find Rerun.app (production mode)
        let appLocations = [
            URL(fileURLWithPath: "/Applications/Rerun.app"),
            execURL.deletingLastPathComponent().appendingPathComponent("Rerun.app"),
        ]

        var appURL: URL?
        for location in appLocations {
            if FileManager.default.fileExists(atPath: location.appendingPathComponent("Contents/MacOS/Rerun").path) {
                appURL = location
                break
            }
        }

        if let appURL {
            // Launch as app bundle for proper TCC identity
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.createsNewApplicationInstance = true

            do {
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            } catch {
                print("Failed to launch Rerun.app: \(error.localizedDescription)")
                throw ExitCode(1)
            }

            guard let newStatus = await DaemonStartupWaiter.waitUntilRunning() else {
                print("Rerun.app launched but the daemon never became healthy.")
                throw ExitCode(1)
            }

            if formatter.useJSON {
                try formatter.printJSON(["status": "started", "pid": "\(newStatus.pid ?? 0)"])
            } else {
                print("Daemon started (PID \(newStatus.pid ?? 0))")
            }
        } else {
            // Development: fall back to bare daemon binary
            let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent("rerun-daemon")

            guard FileManager.default.fileExists(atPath: daemonURL.path) else {
                print("Neither Rerun.app nor rerun-daemon found.")
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
}

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the capture daemon."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() async throws {
        let formatter = OutputFormatter(json: json)
        let hadLaunchAgent = LaunchAgentManager.isInstalled()

        if hadLaunchAgent {
            do {
                try LaunchAgentManager.uninstall()
            } catch {
                print("Failed to remove legacy LaunchAgent: \(error)")
                throw ExitCode(1)
            }
        }

        let status = DaemonDetector.detect()

        guard status.running, let pid = status.pid else {
            if hadLaunchAgent {
                if formatter.useJSON {
                    try formatter.printJSON(["status": "stopped"])
                } else {
                    print("Daemon stopped")
                }
                return
            }

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
