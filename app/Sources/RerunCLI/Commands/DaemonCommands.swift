import ArgumentParser
import AppKit
import Foundation
import RerunCore

enum DaemonLaunchTarget: Equatable {
    case app(URL)
    case binary(URL)

    static func resolve(
        executableURL: URL,
        profile: String,
        preference: DaemonLaunchPreference = .auto,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> DaemonLaunchTarget? {
        let localApps = appBundleCandidates(executableURL: executableURL, profile: profile)
        let localBinary = executableURL.deletingLastPathComponent().appendingPathComponent("rerun-daemon")
        let installedAppURL = installedAppURL(profile: profile)

        func firstExistingApp(in urls: [URL]) -> DaemonLaunchTarget? {
            for appURL in urls {
                if let executablePath = appExecutablePath(for: appURL, profile: profile),
                   fileExists(executablePath) {
                    return .app(appURL)
                }
            }
            return nil
        }

        switch preference {
        case .local:
            if let target = firstExistingApp(in: localApps) {
                return target
            }
            return fileExists(localBinary.path) ? .binary(localBinary) : nil
        case .installed:
            guard let installedAppURL,
                  let executablePath = appExecutablePath(for: installedAppURL, profile: profile),
                  fileExists(executablePath) else {
                return nil
            }
            return .app(installedAppURL)
        case .auto:
            if let target = firstExistingApp(in: localApps) {
                return target
            }
            if fileExists(localBinary.path) {
                return .binary(localBinary)
            }
            guard let installedAppURL,
                  let executablePath = appExecutablePath(for: installedAppURL, profile: profile),
                  fileExists(executablePath) else {
                return nil
            }
            return .app(installedAppURL)
        }
    }

    private static func installedAppURL(profile: String) -> URL? {
        guard let variant = RerunAppVariant.variant(forProfile: profile) else { return nil }
        return URL(fileURLWithPath: "/Applications/\(variant.appName).app")
    }

    private static func appExecutablePath(for appURL: URL, profile: String) -> String? {
        guard let variant = RerunAppVariant.variant(forProfile: profile) else { return nil }
        return appURL.appendingPathComponent("Contents/MacOS/\(variant.executableName)").path
    }
}

enum DaemonLaunchPreference: String, ExpressibleByArgument {
    case auto
    case local
    case installed
}

enum DaemonLaunchContext {
    static func processEnvironment(profile: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["RERUN_PROFILE"] = profile
        return environment
    }

    static func launchArguments(profile: String) -> [String] {
        RerunProfile.launchArguments(profile: profile)
    }
}

extension DaemonLaunchTarget {
    static func appBundleCandidates(executableURL: URL, profile: String) -> [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()
        guard let variant = RerunAppVariant.variant(forProfile: profile) else {
            return []
        }

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                urls.append(url)
            }
        }

        var current = executableURL.deletingLastPathComponent()
        append(current.appendingPathComponent("\(variant.appName).app", isDirectory: true))

        for _ in 0..<6 {
            append(current.appendingPathComponent("\(variant.appName).app", isDirectory: true))
            append(
                current
                    .appendingPathComponent("build", isDirectory: true)
                    .appendingPathComponent("\(variant.appName).app", isDirectory: true)
            )

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return urls
    }
}

enum DaemonStartError: Error, Equatable {
    case appNeverHealthy
    case daemonNeverHealthy
}

enum DaemonStartSupport {
    static func waitForHealthyStartup(
        target: DaemonLaunchTarget,
        waitUntilRunning: () async -> DaemonDetector.DaemonStatus? = {
            await DaemonStartupWaiter.waitUntilRunning()
        }
    ) async throws -> DaemonDetector.DaemonStatus {
        guard let status = await waitUntilRunning() else {
            switch target {
            case .app:
                throw DaemonStartError.appNeverHealthy
            case .binary:
                throw DaemonStartError.daemonNeverHealthy
            }
        }

        return status
    }
}

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start the capture daemon."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Option(name: .long, help: "Launch target: auto, local, or installed.")
    var target: DaemonLaunchPreference = .auto

    func run() async throws {
        let profile = RerunProfile.current()

        if RerunProfile.isDefault(profile), LaunchAgentManager.isInstalled() {
            do {
                try LaunchAgentManager.uninstall()
            } catch {
                print("Failed to remove legacy LaunchAgent: \(error)")
                throw ExitCode(1)
            }
        }

        let status = DaemonDetector.detect(profile: profile)
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

        guard let launchTarget = DaemonLaunchTarget.resolve(executableURL: execURL, profile: profile, preference: target) else {
            print("No matching Rerun launch target found for --target \(target.rawValue).")
            throw ExitCode(1)
        }

        switch launchTarget {
        case .app(let appURL):
            // Launch as app bundle for proper TCC identity
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.createsNewApplicationInstance = true
            config.arguments = DaemonLaunchContext.launchArguments(profile: profile)

            do {
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            } catch {
                print("Failed to launch Rerun.app: \(error.localizedDescription)")
                throw ExitCode(1)
            }

            guard let newStatus = try? await DaemonStartSupport.waitForHealthyStartup(target: launchTarget) else {
                print("Rerun.app launched but the daemon never became healthy.")
                throw ExitCode(1)
            }

            if formatter.useJSON {
                try formatter.printJSON(["status": "started", "pid": "\(newStatus.pid ?? 0)"])
            } else {
                print("Daemon started (PID \(newStatus.pid ?? 0))")
            }
        case .binary(let daemonURL):
            // Development: fall back to bare daemon binary
            let process = Process()
            process.executableURL = daemonURL
            process.arguments = DaemonLaunchContext.launchArguments(profile: profile)
            process.environment = DaemonLaunchContext.processEnvironment(profile: profile)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.qualityOfService = .background

            do {
                try process.run()
            } catch {
                print("Failed to start daemon: \(error.localizedDescription)")
                throw ExitCode(1)
            }

            guard let newStatus = try? await DaemonStartSupport.waitForHealthyStartup(target: launchTarget) else {
                print("rerun-daemon launched but the daemon never became healthy.")
                throw ExitCode(1)
            }

            let pid = newStatus.pid ?? Int(process.processIdentifier)
            if formatter.useJSON {
                try formatter.printJSON(["status": "started", "pid": "\(pid)"])
            } else {
                print("Daemon started (PID \(pid))")
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
        let profile = RerunProfile.current()
        let formatter = OutputFormatter(json: json)
        let hadLaunchAgent = RerunProfile.isDefault(profile) && LaunchAgentManager.isInstalled()

        if hadLaunchAgent {
            do {
                try LaunchAgentManager.uninstall()
            } catch {
                print("Failed to remove legacy LaunchAgent: \(error)")
                throw ExitCode(1)
            }
        }

        let status = DaemonDetector.detect(profile: profile)

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
