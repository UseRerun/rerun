import Foundation

public enum RerunHome {
    public static func baseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["RERUN_HOME"] {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("rerun", isDirectory: true)
    }

    public static func capturesURL() -> URL {
        baseURL().appendingPathComponent("captures", isDirectory: true)
    }

    public static func pauseFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Rerun", isDirectory: true)
        return appSupport.appendingPathComponent("paused")
    }

    public static func pidFileURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Rerun", isDirectory: true)
        return appSupport.appendingPathComponent("daemon.pid")
    }
}
