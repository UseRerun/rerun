import Foundation

public enum RerunProfile {
    public static let defaultName = "default"

    public static func current(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let argument = profileArgument(in: arguments) {
            return normalized(argument)
        }
        if let environmentValue = environment["RERUN_PROFILE"] {
            return normalized(environmentValue)
        }
        if let inferred = inferredDefaultProfile(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processName: ProcessInfo.processInfo.processName
        ) {
            return inferred
        }
        return defaultName
    }

    public static func normalized(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return defaultName }
        if trimmed == defaultName { return defaultName }

        var slug = ""
        var previousWasSeparator = false
        for scalar in trimmed.unicodeScalars {
            let isAllowed = CharacterSet.alphanumerics.contains(scalar)
            if isAllowed {
                slug.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                slug.append("-")
                previousWasSeparator = true
            }
        }

        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? defaultName : slug
    }

    public static func isDefault(_ profile: String = current()) -> Bool {
        normalized(profile) == defaultName
    }

    public static func homeDirectoryName(profile: String = current()) -> String {
        let profile = normalized(profile)
        return isDefault(profile) ? "rerun" : "rerun-\(profile)"
    }

    public static func appSupportDirectoryName(profile: String = current()) -> String {
        let profile = normalized(profile)
        return isDefault(profile) ? "Rerun" : "Rerun-\(profile)"
    }

    public static func launchArguments(profile: String = current()) -> [String] {
        let profile = normalized(profile)
        guard !isDefault(profile) else { return [] }
        return ["--profile", profile]
    }

    static func inferredDefaultProfile(bundleIdentifier: String?, processName: String?) -> String? {
        RerunAppVariant.inferredProfile(bundleIdentifier: bundleIdentifier, processName: processName)
    }

    private static func profileArgument(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--profile", index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if argument.hasPrefix("--profile=") {
                return String(argument.dropFirst("--profile=".count))
            }
        }
        return nil
    }
}
