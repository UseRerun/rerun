import Testing
import RerunCore
@testable import RerunCLI

@Suite("DaemonStartupWaiter")
struct DaemonStartupWaiterTests {
    @Test func waitsUntilDaemonReportsRunning() async {
        var responses: [DaemonDetector.DaemonStatus] = [
            .init(running: false, pid: nil),
            .init(running: false, pid: nil),
            .init(running: true, pid: 4242),
        ]

        let status = await DaemonStartupWaiter.waitUntilRunning(
            maxAttempts: responses.count,
            pollInterval: .zero,
            detect: { responses.removeFirst() },
            sleep: { _ in }
        )

        #expect(status == .init(running: true, pid: 4242))
        #expect(responses.isEmpty)
    }

    @Test func returnsNilWhenDaemonNeverStarts() async {
        var attempts = 0

        let status = await DaemonStartupWaiter.waitUntilRunning(
            maxAttempts: 3,
            pollInterval: .zero,
            detect: {
                attempts += 1
                return .init(running: false, pid: nil)
            },
            sleep: { _ in }
        )

        #expect(status == nil)
        #expect(attempts == 3)
    }
}
