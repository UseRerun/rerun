import Testing
import RerunCore
@testable import RerunDaemon

@Suite("OnboardingRequirements")
struct OnboardingRequirementsTests {
    @Test func productionShowsOptionalAppManagementPrompt() {
        let requirements = OnboardingRequirements(
            appVariant: .production,
            accessibilityGranted: true,
            screenRecordingGranted: true,
            modelReady: true,
            appManagementPromptDismissed: false
        )

        #expect(requirements.isComplete)
        #expect(requirements.showsAppManagementPrompt)
        #expect(requirements.shouldShowOnboarding)
    }

    @Test func developmentSkipsAppManagementPrompt() {
        let requirements = OnboardingRequirements(
            appVariant: .development,
            accessibilityGranted: true,
            screenRecordingGranted: true,
            modelReady: true,
            appManagementPromptDismissed: false
        )

        #expect(requirements.isComplete)
        #expect(!requirements.showsAppManagementPrompt)
        #expect(!requirements.shouldShowOnboarding)
    }

    @Test func dismissedProductionPromptStaysDismissedWhenCoreSetupIsDone() {
        let requirements = OnboardingRequirements(
            appVariant: .production,
            accessibilityGranted: true,
            screenRecordingGranted: true,
            modelReady: true,
            appManagementPromptDismissed: true
        )

        #expect(requirements.isComplete)
        #expect(!requirements.showsAppManagementPrompt)
        #expect(!requirements.shouldShowOnboarding)
    }

    @Test func missingCorePermissionsStillShowOnboarding() {
        let requirements = OnboardingRequirements(
            appVariant: .development,
            accessibilityGranted: false,
            screenRecordingGranted: true,
            modelReady: true,
            appManagementPromptDismissed: true
        )

        #expect(!requirements.isComplete)
        #expect(!requirements.showsAppManagementPrompt)
        #expect(requirements.shouldShowOnboarding)
    }
}
