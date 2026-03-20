import Foundation

/// Orchestrates text capture: tries Accessibility first, falls back to OCR.
///
/// Strategy: A11y is near-zero CPU and instant, so we always try it first.
/// If the extracted text is below the minimum threshold (50 chars),
/// we fall back to screenshot + OCR. Metadata from A11y (window title, URL)
/// is preserved even when OCR provides the text content.
public final class CaptureOrchestrator: @unchecked Sendable {
    private let accessibilityExtractor: AccessibilityExtractor
    private let ocrExtractor: OCRExtractor

    public init(
        accessibilityExtractor: AccessibilityExtractor = .init(),
        ocrExtractor: OCRExtractor = .init()
    ) {
        self.accessibilityExtractor = accessibilityExtractor
        self.ocrExtractor = ocrExtractor
    }

    /// Capture text from the focused window using the best available method.
    ///
    /// Returns `nil` only if both A11y and OCR fail completely.
    public func capture() async -> CaptureResult? {
        // Try accessibility first — fast and lightweight
        let axResult = accessibilityExtractor.extract()

        // If AX got enough text, use it directly
        if let ax = axResult, !ax.needsOCRFallback {
            return ax
        }

        // Fall back to OCR for text content
        if let ocrResult = await ocrExtractor.extract() {
            // Merge: OCR text + AX metadata (window title, URL are richer from AX)
            return CaptureResult(
                text: ocrResult.text,
                appName: axResult?.appName ?? ocrResult.appName,
                bundleId: axResult?.bundleId ?? ocrResult.bundleId,
                windowTitle: axResult?.windowTitle,
                url: axResult?.url,
                source: .ocr
            )
        }

        // Both failed or AX had some text — return whatever AX got (even if short)
        return axResult
    }
}
