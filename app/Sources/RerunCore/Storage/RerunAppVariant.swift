import Foundation

public enum RerunAppVariant: CaseIterable {
    case production
    case development

    public var profile: String {
        switch self {
        case .production: return RerunProfile.defaultName
        case .development: return "dev"
        }
    }

    public var appName: String {
        switch self {
        case .production: return "Rerun"
        case .development: return "RerunDev"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .production: return "com.rerun.app"
        case .development: return "com.rerun.dev"
        }
    }

    public var executableName: String {
        appName
    }

    public static func variant(forProfile profile: String) -> RerunAppVariant? {
        switch RerunProfile.normalized(profile) {
        case RerunProfile.defaultName: return .production
        case "dev": return .development
        default: return nil
        }
    }

    public static func variant(bundleIdentifier: String?) -> RerunAppVariant? {
        allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }

    public static func inferredProfile(bundleIdentifier: String?, processName: String?) -> String? {
        if let variant = variant(bundleIdentifier: bundleIdentifier) {
            return variant.profile
        }

        guard let processName else { return nil }
        return allCases.first(where: { $0.executableName == processName })?.profile
    }
}
