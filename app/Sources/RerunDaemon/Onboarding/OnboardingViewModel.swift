import AppKit
import RerunCore

struct OnboardingRequirements {
    let appVariant: RerunAppVariant
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let modelReady: Bool
    let appManagementPromptDismissed: Bool

    var isComplete: Bool {
        accessibilityGranted && screenRecordingGranted && modelReady
    }

    var showsAppManagementPrompt: Bool {
        appVariant == .production && !appManagementPromptDismissed
    }

    var shouldShowOnboarding: Bool {
        !accessibilityGranted || !screenRecordingGranted || showsAppManagementPrompt
    }
}

@Observable
@MainActor
final class OnboardingViewModel {
    var accessibilityGranted: Bool = false
    var screenRecordingGranted: Bool = false
    var modelState: ModelManager.ModelState = .idle
    var appManagementPromptDismissed: Bool = false

    var isComplete: Bool {
        requirements.isComplete
    }

    var shouldShowOnboarding: Bool {
        requirements.shouldShowOnboarding
    }

    var showsAppManagementPrompt: Bool {
        requirements.showsAppManagementPrompt
    }

    private var modelReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    private var requirements: OnboardingRequirements {
        OnboardingRequirements(
            appVariant: appVariant,
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted,
            modelReady: modelReady,
            appManagementPromptDismissed: appManagementPromptDismissed
        )
    }

    private var pollTimer: Timer?
    private let modelManager: ModelManager
    private let appVariant: RerunAppVariant

    private static let appManagementPromptDismissedKey = "onboardingAppManagementPromptDismissed"

    init(modelManager: ModelManager, appVariant: RerunAppVariant) {
        self.modelManager = modelManager
        self.appVariant = appVariant
        self.accessibilityGranted = AccessibilityExtractor.isAccessibilityGranted
        self.screenRecordingGranted = OCRExtractor.isScreenRecordingGranted
        self.modelState = modelManager.state
        self.appManagementPromptDismissed = UserDefaults.standard.bool(
            forKey: Self.appManagementPromptDismissedKey
        )

        startPolling()
    }

    func requestAccessibility() {
        AccessibilityExtractor.requestAccessibilityIfNeeded()
    }

    func requestScreenRecording() {
        OCRExtractor.requestScreenRecordingIfNeeded()
    }

    func openAppManagementSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement") {
            NSWorkspace.shared.open(url)
        }
    }

    func dismissAppManagementPrompt() {
        guard showsAppManagementPrompt else { return }
        appManagementPromptDismissed = true
        UserDefaults.standard.set(true, forKey: Self.appManagementPromptDismissedKey)
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accessibilityGranted = AccessibilityExtractor.isAccessibilityGranted
                self.screenRecordingGranted = OCRExtractor.isScreenRecordingGranted
                self.modelState = self.modelManager.state
            }
        }
    }
}
