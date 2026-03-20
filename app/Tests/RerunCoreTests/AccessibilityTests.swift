import Testing
@testable import RerunCore

@Suite("AccessibilityExtractor")
struct AccessibilityTests {
    @Test func captureResultInitialization() {
        let result = CaptureResult(
            text: "Hello world from Safari",
            appName: "Safari",
            bundleId: "com.apple.Safari",
            windowTitle: "Google - Safari",
            url: "https://google.com",
            source: .accessibility
        )
        #expect(result.text == "Hello world from Safari")
        #expect(result.appName == "Safari")
        #expect(result.bundleId == "com.apple.Safari")
        #expect(result.windowTitle == "Google - Safari")
        #expect(result.url == "https://google.com")
        #expect(result.source == .accessibility)
        #expect(result.needsOCRFallback == false)
    }

    @Test func captureResultWithOCRFallback() {
        let result = CaptureResult(
            text: "short",
            appName: "SomeApp",
            source: .accessibility,
            needsOCRFallback: true
        )
        #expect(result.needsOCRFallback == true)
        #expect(result.bundleId == nil)
        #expect(result.windowTitle == nil)
        #expect(result.url == nil)
    }

    @Test func textSourceRawValues() {
        #expect(CaptureResult.TextSource.accessibility.rawValue == "accessibility")
        #expect(CaptureResult.TextSource.ocr.rawValue == "ocr")
    }

    @Test func minimumTextLengthThreshold() {
        #expect(AccessibilityExtractor.minimumTextLength == 50)
    }

    @Test func extractorInitializesWithDefaults() {
        let extractor = AccessibilityExtractor()
        // Verify it creates without crashing — check a known default
        #expect(AccessibilityExtractor.minimumTextLength == 50)
        _ = extractor
    }

    @Test func extractorInitializesWithCustomValues() {
        let extractor = AccessibilityExtractor(maxDepth: 2, maxChildrenPerNode: 10, timeoutSeconds: 0.5)
        _ = extractor
    }

    @Test func permissionCheckDoesNotCrash() {
        // This will return true or false depending on test environment
        let _ = AccessibilityExtractor.isAccessibilityGranted
    }

    // Integration test (extract from real window) omitted — requires CG session.
    // Use `swift run rerun-daemon --test-ax` for manual integration testing.
}
