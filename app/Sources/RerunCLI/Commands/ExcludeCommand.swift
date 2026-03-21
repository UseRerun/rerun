import ArgumentParser
import Foundation
import RerunCore

struct ExcludeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exclude",
        abstract: "Manage capture exclusions.",
        discussion: """
            Examples:
              rerun exclude list                              List all exclusions
              rerun exclude add app com.example.App           Exclude an app by bundle ID
              rerun exclude add domain *.bankofamerica.com    Exclude a domain
              rerun exclude remove app com.example.App        Remove an exclusion
            """,
        subcommands: [
            AddExclusion.self,
            ListExclusions.self,
            RemoveExclusion.self,
        ],
        defaultSubcommand: ListExclusions.self
    )
}

struct AddExclusion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a capture exclusion."
    )

    @Argument(help: "Exclusion type: app or domain.")
    var type: String

    @Argument(help: "Value to exclude (bundle ID or domain pattern).")
    var value: String

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        guard type == "app" || type == "domain" else {
            print("Invalid type: \(type). Use: app or domain")
            throw ExitCode(2)
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())

        if try await db.exclusionExists(type: type, value: value) {
            let formatter = OutputFormatter(json: json, noColor: noColor)
            if formatter.useJSON {
                try formatter.printJSON(["status": "exists", "type": type, "value": value])
            } else {
                print("Exclusion already exists: \(type) \(value)")
            }
            return
        }

        let exclusion = Exclusion(type: type, value: value)
        try await db.insertExclusion(exclusion)

        let formatter = OutputFormatter(json: json, noColor: noColor)
        if formatter.useJSON {
            try formatter.printJSON(exclusion)
        } else {
            print("Added \(type) exclusion: \(value)")
        }
    }
}

struct ListExclusions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all exclusions."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let exclusions = try await db.fetchExclusions()
        let formatter = OutputFormatter(json: json, noColor: noColor)

        if formatter.useJSON {
            try formatter.printJSON(exclusions)
        } else if exclusions.isEmpty {
            print("No exclusions configured.")
        } else {
            for exclusion in exclusions {
                print("\(exclusion.type)\t\(exclusion.value)")
            }
            print("\n\(exclusions.count) exclusion\(exclusions.count == 1 ? "" : "s")")
        }
    }
}

struct RemoveExclusion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a capture exclusion."
    )

    @Argument(help: "Exclusion type: app or domain.")
    var type: String

    @Argument(help: "Value to remove (bundle ID or domain pattern).")
    var value: String

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor = false

    func run() async throws {
        guard type == "app" || type == "domain" else {
            print("Invalid type: \(type). Use: app or domain")
            throw ExitCode(2)
        }

        let db = try DatabaseManager(path: DatabaseManager.defaultPath())
        let exclusions = try await db.fetchExclusions()

        guard let match = exclusions.first(where: { $0.type == type && $0.value == value }) else {
            let formatter = OutputFormatter(json: json, noColor: noColor)
            if formatter.useJSON {
                try formatter.printJSON(["status": "not_found", "type": type, "value": value])
            } else {
                print("Exclusion not found: \(type) \(value)")
            }
            throw ExitCode(4)
        }

        _ = try await db.deleteExclusion(id: match.id)

        let formatter = OutputFormatter(json: json, noColor: noColor)
        if formatter.useJSON {
            try formatter.printJSON(["status": "removed", "type": type, "value": value])
        } else {
            print("Removed \(type) exclusion: \(value)")
        }
    }
}
