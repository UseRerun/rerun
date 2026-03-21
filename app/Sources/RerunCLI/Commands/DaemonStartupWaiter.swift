import Foundation
import RerunCore

enum DaemonStartupWaiter {
    static func waitUntilRunning(
        maxAttempts: Int = 50,
        pollInterval: Duration = .milliseconds(100),
        detect: () -> DaemonDetector.DaemonStatus = { DaemonDetector.detect() },
        sleep: (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) async -> DaemonDetector.DaemonStatus? {
        guard maxAttempts > 0 else { return nil }

        for attempt in 0..<maxAttempts {
            let status = detect()
            if status.running {
                return status
            }

            if attempt < maxAttempts - 1 {
                await sleep(pollInterval)
            }
        }

        return nil
    }
}
