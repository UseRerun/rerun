package struct CapturePauseState: Sendable {
    package private(set) var isManuallyPaused = false
    package private(set) var isSystemPaused = false

    package init() {}

    package var isPaused: Bool {
        isManuallyPaused || isSystemPaused
    }

    package mutating func pauseManual() {
        isManuallyPaused = true
    }

    package mutating func resumeManual() {
        isManuallyPaused = false
    }

    package mutating func pauseSystem() {
        isSystemPaused = true
    }

    package mutating func resumeSystem() {
        isSystemPaused = false
    }
}
