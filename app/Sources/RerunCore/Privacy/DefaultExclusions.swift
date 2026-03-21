import Foundation

/// Default app exclusions seeded on first run.
public enum DefaultExclusions {
    /// Bundle IDs that should never be captured.
    public static let apps: [(bundleId: String, label: String)] = [
        ("com.1password.1password", "1Password"),
        ("com.agilebits.onepassword7", "1Password 7"),
        ("com.bitwarden.desktop", "Bitwarden"),
        ("com.lastpass.LastPass", "LastPass"),
        ("com.callpod.keeperFill", "Keeper"),
        ("com.dashlane.Dashlane", "Dashlane"),
        ("com.apple.systempreferences", "System Settings"),
        ("com.apple.Passwords", "Passwords"),
        ("com.rerun.daemon", "Rerun"),
    ]

    static let safariPrivateBrowsingBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    static let chromiumPrivateBrowsingBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    static let edgePrivateBrowsingBundleIds: Set<String> = [
        "com.microsoft.edgemac",
    ]

    static let firefoxPrivateBrowsingBundleIds: Set<String> = [
        "org.mozilla.firefox",
    ]

    package static let privacySensitiveBrowserBundleIds =
        safariPrivateBrowsingBundleIds
        .union(chromiumPrivateBrowsingBundleIds)
        .union(edgePrivateBrowsingBundleIds)
        .union(firefoxPrivateBrowsingBundleIds)

    package static func requiresAccessibilityMetadata(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return privacySensitiveBrowserBundleIds.contains(bundleId)
    }
}
