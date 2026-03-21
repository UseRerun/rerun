import Foundation

public struct RerunStats: Codable, Sendable {
    public let version: String
    public let daemonRunning: Bool
    public let daemonPID: Int?
    public let totalCaptures: Int
    public let oldestCapture: String?
    public let newestCapture: String?
    public let databaseSizeBytes: Int64
    public let capturesSizeBytes: Int64
}

public struct StatsProvider: Sendable {
    public static func gatherStats(db: DatabaseManager) async throws -> RerunStats {
        let daemon = DaemonDetector.detect()
        let count = try await db.captureCount()
        let oldest = try await db.oldestCaptureTimestamp()
        let newest = try await db.newestCaptureTimestamp()
        let dbSize = Self.fileSize(atPath: try DatabaseManager.defaultPath())
        let capturesSize = Self.directorySize(at: RerunHome.capturesURL())

        return RerunStats(
            version: Rerun.version,
            daemonRunning: daemon.running,
            daemonPID: daemon.pid,
            totalCaptures: count,
            oldestCapture: oldest,
            newestCapture: newest,
            databaseSizeBytes: dbSize,
            capturesSizeBytes: capturesSize
        )
    }

    private static func fileSize(atPath path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
