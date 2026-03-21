import Foundation
import Testing
import RerunCore
@testable import RerunCLI

@Suite("StartCommand")
struct StartCommandTests {
    @Test func prefersLocalAppBundleOverLocalDaemonAndInstalledApp() {
        let execURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/.build/arm64-apple-macosx/debug/rerun")
        let localAppURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/build/Rerun.app", isDirectory: true)
        let localDaemonURL = execURL.deletingLastPathComponent().appendingPathComponent("rerun-daemon")
        let installedAppURL = URL(fileURLWithPath: "/Applications/Rerun.app", isDirectory: true)

        let existingPaths: Set<String> = [
            localAppURL.appendingPathComponent("Contents/MacOS/Rerun").path,
            localDaemonURL.path,
            installedAppURL.appendingPathComponent("Contents/MacOS/Rerun").path,
        ]

        let target = DaemonLaunchTarget.resolve(executableURL: execURL, profile: "default") { existingPaths.contains($0) }

        #expect(target == .app(localAppURL))
    }

    @Test func prefersLocalDaemonOverInstalledApp() {
        let execURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/.build/arm64-apple-macosx/debug/rerun")
        let localDaemonURL = execURL.deletingLastPathComponent().appendingPathComponent("rerun-daemon")
        let installedAppURL = URL(fileURLWithPath: "/Applications/Rerun.app", isDirectory: true)

        let existingPaths: Set<String> = [
            localDaemonURL.path,
            installedAppURL.appendingPathComponent("Contents/MacOS/Rerun").path,
        ]

        let target = DaemonLaunchTarget.resolve(executableURL: execURL, profile: "default") { existingPaths.contains($0) }

        #expect(target == .binary(localDaemonURL))
    }

    @Test func fallsBackToInstalledAppWhenNoLocalArtifactsExist() {
        let execURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/.build/arm64-apple-macosx/debug/rerun")
        let installedAppURL = URL(fileURLWithPath: "/Applications/Rerun.app", isDirectory: true)

        let target = DaemonLaunchTarget.resolve(executableURL: execURL, profile: "default") {
            $0 == installedAppURL.appendingPathComponent("Contents/MacOS/Rerun").path
        }

        #expect(target == .app(installedAppURL))
    }

    @Test func installedPreferenceSkipsLocalArtifacts() {
        let execURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/.build/arm64-apple-macosx/debug/rerun")
        let localAppURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/build/Rerun.app", isDirectory: true)
        let installedAppURL = URL(fileURLWithPath: "/Applications/Rerun.app", isDirectory: true)

        let existingPaths: Set<String> = [
            localAppURL.appendingPathComponent("Contents/MacOS/Rerun").path,
            installedAppURL.appendingPathComponent("Contents/MacOS/Rerun").path,
        ]

        let target = DaemonLaunchTarget.resolve(
            executableURL: execURL,
            profile: "default",
            preference: .installed
        ) { existingPaths.contains($0) }

        #expect(target == .app(installedAppURL))
    }

    @Test func devProfileFindsRerunDevApp() {
        let execURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/.build/arm64-apple-macosx/debug/rerun")
        let localDevAppURL = URL(fileURLWithPath: "/tmp/rerun-tests/app/build/RerunDev.app", isDirectory: true)
        let installedDevAppURL = URL(fileURLWithPath: "/Applications/RerunDev.app", isDirectory: true)

        let existingPaths: Set<String> = [
            localDevAppURL.appendingPathComponent("Contents/MacOS/RerunDev").path,
            installedDevAppURL.appendingPathComponent("Contents/MacOS/RerunDev").path,
        ]

        let target = DaemonLaunchTarget.resolve(executableURL: execURL, profile: "dev") { existingPaths.contains($0) }

        #expect(target == .app(localDevAppURL))
    }

    @Test func launchArgumentsAreEmptyForDefaultProfile() {
        #expect(DaemonLaunchContext.launchArguments(profile: "default").isEmpty)
        #expect(DaemonLaunchContext.launchArguments(profile: "dev") == ["--profile", "dev"])
    }

    @Test func waitForHealthyStartupReturnsDetectedStatus() async throws {
        let expected = DaemonDetector.DaemonStatus(running: true, pid: 4242)

        let status = try await DaemonStartSupport.waitForHealthyStartup(target: .binary(URL(fileURLWithPath: "/tmp/rerun-daemon"))) {
            expected
        }

        #expect(status == expected)
    }

    @Test func waitForHealthyStartupThrowsWhenDaemonNeverBecomesHealthy() async {
        await #expect(throws: DaemonStartError.daemonNeverHealthy) {
            try await DaemonStartSupport.waitForHealthyStartup(target: .binary(URL(fileURLWithPath: "/tmp/rerun-daemon"))) {
                nil
            }
        }
    }
}
