import ArgumentParser
import RerunCore

@main
struct RerunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rerun",
        abstract: "Local, always-on screen memory for macOS.",
        version: Rerun.version,
        subcommands: [
            StatusCommand.self,
        ],
        defaultSubcommand: nil
    )
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show Rerun daemon status and capture statistics."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() throws {
        if json {
            print("""
            {"version":"\(Rerun.version)","status":"not running","captures":0}
            """)
        } else {
            print("Rerun v\(Rerun.version)")
            print("Status: not running")
            print("Captures: 0")
        }
    }
}
