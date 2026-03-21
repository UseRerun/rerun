import Testing
@testable import RerunCore

@Suite("Privacy helpers")
struct PrivacyHelpersTests {
    @Test func browserBundlesRequireAccessibilityMetadata() {
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: "com.apple.Safari"))
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: "com.google.Chrome"))
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: "org.mozilla.firefox"))
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: "com.microsoft.edgemac"))
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: "com.apple.TextEdit") == false)
        #expect(DefaultExclusions.requiresAccessibilityMetadata(bundleId: nil) == false)
    }

    @Test func rerunSelfExclusionsCoverBundledAppAndDaemon() {
        let bundleIds = Set(DefaultExclusions.apps.map(\.bundleId))

        #expect(bundleIds.contains("com.rerun.daemon"))
        #expect(bundleIds.contains("com.rerun.app"))
        #expect(bundleIds.contains("com.rerun.dev"))
    }

    @Test func manualPauseSurvivesSystemWake() {
        var state = CapturePauseState()

        state.pauseManual()
        #expect(state.isPaused)

        state.pauseSystem()
        #expect(state.isPaused)

        state.resumeSystem()
        #expect(state.isPaused)

        state.resumeManual()
        #expect(state.isPaused == false)
    }
}
