import Testing
@testable import RerunCore

@Suite("OCR Pipeline")
struct OCRTests {
    @Test func ocrExtractorInitializesWithDefaults() {
        let extractor = OCRExtractor()
        _ = extractor
    }

    @Test func ocrExtractorInitializesWithCustomConfidence() {
        let extractor = OCRExtractor(minimumConfidence: 0.5)
        _ = extractor
    }

    @Test func screenRecordingPermissionCheckDoesNotCrash() {
        let _ = OCRExtractor.isScreenRecordingGranted
    }

    @Test func ocrCaptureResultUsesOCRSource() {
        let result = CaptureResult(
            text: "OCR extracted text from a screenshot",
            appName: "Preview",
            bundleId: "com.apple.Preview",
            source: .ocr
        )
        #expect(result.source == .ocr)
        #expect(result.text == "OCR extracted text from a screenshot")
        #expect(result.needsOCRFallback == false)
    }

    @Test func captureOrchestratorInitializes() {
        let orchestrator = CaptureOrchestrator()
        _ = orchestrator
    }

    @Test func captureOrchestratorWithCustomExtractors() {
        let ax = AccessibilityExtractor(maxDepth: 2)
        let ocr = OCRExtractor(minimumConfidence: 0.5)
        let orchestrator = CaptureOrchestrator(accessibilityExtractor: ax, ocrExtractor: ocr)
        _ = orchestrator
    }
}
