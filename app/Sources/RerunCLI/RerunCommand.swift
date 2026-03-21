import ArgumentParser
import RerunCore

@main
struct RerunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rerun",
        abstract: "Local, always-on screen memory for macOS.",
        version: Rerun.version,
        subcommands: [
            StatusCommand.self,
        ]
    )
}
