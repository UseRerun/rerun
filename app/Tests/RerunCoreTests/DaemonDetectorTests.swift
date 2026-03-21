import Foundation
import Testing
@testable import RerunCore

@Suite("DaemonDetector")
struct DaemonDetectorTests {

    @Test func acceptsMatchingPIDFileProcess() throws {
        let pidFileURL = makeTempPIDFileURL()
        defer { try? FileManager.default.removeItem(at: pidFileURL) }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        try "\(currentPID)".write(to: pidFileURL, atomically: true, encoding: .utf8)

        let processName = try #require(DaemonDetector.commandName(for: currentPID))
        let status = DaemonDetector.detect(
            pidFileURL: pidFileURL,
            expectedProcessName: processName
        ) {
            .init(running: false, pid: nil)
        }

        #expect(status == .init(running: true, pid: currentPID))
    }

    @Test func rejectsMismatchedPIDFileProcess() throws {
        let pidFileURL = makeTempPIDFileURL()
        defer { try? FileManager.default.removeItem(at: pidFileURL) }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        try "\(currentPID)".write(to: pidFileURL, atomically: true, encoding: .utf8)

        let status = DaemonDetector.detect(
            pidFileURL: pidFileURL,
            expectedProcessName: "rerun-daemon"
        ) {
            .init(running: false, pid: nil)
        }

        #expect(status == .init(running: false, pid: nil))
        #expect(!FileManager.default.fileExists(atPath: pidFileURL.path))
    }

    @Test func acceptsLaterExpectedProcessNameWithoutDeletingPIDFile() throws {
        let pidFileURL = makeTempPIDFileURL()
        defer { try? FileManager.default.removeItem(at: pidFileURL) }

        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        try "\(currentPID)".write(to: pidFileURL, atomically: true, encoding: .utf8)

        let processName = try #require(DaemonDetector.commandName(for: currentPID))
        let status = DaemonDetector.detect(
            pidFileURL: pidFileURL,
            expectedProcessNames: ["Rerun", processName]
        ) {
            .init(running: false, pid: nil)
        }

        #expect(status == .init(running: true, pid: currentPID))
        #expect(FileManager.default.fileExists(atPath: pidFileURL.path))
    }

    private func makeTempPIDFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.pid")
    }
}
