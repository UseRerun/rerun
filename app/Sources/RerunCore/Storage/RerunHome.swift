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
}
