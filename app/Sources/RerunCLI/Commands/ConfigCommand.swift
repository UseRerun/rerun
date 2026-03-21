import ArgumentParser
import Foundation
import RerunCore

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View current configuration.",
        discussion: """
            Examples:
              rerun config                    Show all configuration
              rerun config rerun_home         Show a specific key
              rerun config --json             Output as JSON
            """
    )

    @Argument(help: "Config key to display (optional).")
    var key: String? = nil

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    private static let knownKeys = ["rerun_home", "database_path", "capture_interval", "exclusion_count", "version"]

    func run() async throws {
        let formatter = OutputFormatter(json: json, noColor: noColor)
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let exclusionCount = try await db.fetchExclusions().count

        let config: [(String, String)] = [
            ("rerun_home", RerunHome.baseURL().path),
            ("database_path", try DatabaseManager.defaultPath()),
            ("capture_interval", "10s"),
            ("exclusion_count", "\(exclusionCount)"),
            ("version", Rerun.version),
        ]

        if let key {
            guard Self.knownKeys.contains(key) else {
                print("Unknown config key: \(key). Known keys: \(Self.knownKeys.joined(separator: ", "))")
                throw ExitCode(2)
            }
            let value = config.first(where: { $0.0 == key })!.1
            if formatter.useJSON {
                try formatter.printJSON([key: value])
            } else {
                print(value)
            }
        } else {
            if formatter.useJSON {
                let dict = Dictionary(uniqueKeysWithValues: config)
                try formatter.printJSON(dict)
            } else {
                for (k, v) in config {
                    print("\(k)\t\(v)")
                }
            }
        }
    }
}
