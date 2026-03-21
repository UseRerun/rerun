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
            SearchCommand.self,
            RecallCommand.self,
            ExcludeCommand.self,
            ExportCommand.self,
            StartCommand.self,
            StopCommand.self,
            PauseCommand.self,
            ResumeCommand.self,
            ConfigCommand.self,
            SummaryCommand.self,
        ]
    )
}
