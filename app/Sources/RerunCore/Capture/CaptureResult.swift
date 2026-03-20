import Foundation

/// Result of a text extraction attempt (Accessibility or OCR).
public struct CaptureResult: Sendable {
    public let text: String
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?
    public let url: String?
    public let source: TextSource
    public let needsOCRFallback: Bool

    public enum TextSource: String, Sendable {
        case accessibility
        case ocr
    }

    public init(
        text: String,
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        source: TextSource,
        needsOCRFallback: Bool = false
    ) {
        self.text = text
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.source = source
        self.needsOCRFallback = needsOCRFallback
    }
}
