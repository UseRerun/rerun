import Foundation

public enum RerunHome {
    public static func baseURL(profile: String = RerunProfile.current()) -> URL {
        if let override = ProcessInfo.processInfo.environment["RERUN_HOME"] {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(RerunProfile.homeDirectoryName(profile: profile), isDirectory: true)
    }

    public static func capturesURL(profile: String = RerunProfile.current()) -> URL {
        baseURL(profile: profile).appendingPathComponent("captures", isDirectory: true)
    }

    public static func appSupportURL(profile: String = RerunProfile.current()) -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(RerunProfile.appSupportDirectoryName(profile: profile), isDirectory: true)
    }

    public static func databaseURL(profile: String = RerunProfile.current()) -> URL {
        appSupportURL(profile: profile).appendingPathComponent("rerun.db")
    }

    public static func pauseFileURL(profile: String = RerunProfile.current()) -> URL {
        appSupportURL(profile: profile).appendingPathComponent("paused")
    }

    public static func pidFileURL(profile: String = RerunProfile.current()) -> URL {
        appSupportURL(profile: profile).appendingPathComponent("daemon.pid")
    }
}
