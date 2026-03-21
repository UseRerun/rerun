import ApplicationServices
import AppKit

/// Extracts text from the focused window using macOS Accessibility APIs.
///
/// Primary capture mechanism — near-zero CPU, instant, works for most apps.
/// Falls back to signaling OCR when extracted text is below the minimum threshold.
public final class AccessibilityExtractor: @unchecked Sendable {
    /// Minimum characters of AX text before we accept it (below this, signal OCR fallback).
    public static let minimumTextLength = 50

    private let maxDepth: Int
    private let maxChildrenPerNode: Int
    private let timeoutSeconds: TimeInterval

    public init(maxDepth: Int = 8, maxChildrenPerNode: Int = 30, timeoutSeconds: TimeInterval = 0.2) {
        self.maxDepth = maxDepth
        self.maxChildrenPerNode = maxChildrenPerNode
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: - Public API

    /// Check if the current process has Accessibility permission.
    public static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Check permission and prompt user to grant it if not already granted.
    @discardableResult
    public static func requestAccessibilityIfNeeded() -> Bool {
        // Use string literal — kAXTrustedCheckOptionPrompt is a mutable C global, not concurrency-safe
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Extract text and metadata from the currently focused window.
    ///
    /// Returns `nil` if no focused app/window is found or if accessibility is not granted.
    /// Sets `needsOCRFallback = true` when extracted text is below the minimum threshold.
    public func extract() -> CaptureResult? {
        guard Self.isAccessibilityGranted else { return nil }

        // Get frontmost app metadata via NSWorkspace (more reliable than AX for this)
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier

        // Create AX element from PID — more reliable than system-wide → focused app
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        // Get focused window for title + URL
        let windowElement = copyElement(from: appElement, attribute: kAXFocusedWindowAttribute)
        let windowTitle = windowElement.flatMap { copyStringValue(from: $0, attribute: kAXTitleAttribute) }

        // Extract URL (browser-specific)
        let url = extractURL(appElement: appElement, windowElement: windowElement, bundleId: bundleId)

        // Walk the AX tree to collect text
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var textParts = Set<String>()

        // Walk both focused element subtree and focused window subtree
        if let focused = copyElement(from: appElement, attribute: kAXFocusedUIElementAttribute) {
            collectText(from: focused, depth: 0, deadline: deadline, into: &textParts)
        }
        if let window = windowElement {
            collectText(from: window, depth: 0, deadline: deadline, into: &textParts)
        }

        let text = textParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")

        let needsFallback = text.count < Self.minimumTextLength

        return CaptureResult(
            text: text,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            source: .accessibility,
            needsOCRFallback: needsFallback
        )
    }

    // MARK: - Tree Walking

    private func collectText(from element: AXUIElement, depth: Int, deadline: Date, into output: inout Set<String>) {
        guard depth <= maxDepth, Date() < deadline else { return }

        // Batch-fetch text attributes for efficiency (one IPC call instead of four)
        let attrs: [String] = [
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXSelectedTextAttribute,
        ]
        let values = batchCopyValues(from: element, attributes: attrs)
        for value in values {
            if let text = flattenText(value), !text.isEmpty {
                output.insert(text)
            }
        }

        // Recurse into children — prefer visible children first
        for childAttr in [kAXVisibleChildrenAttribute, kAXChildrenAttribute] {
            let children = copyChildren(from: element, attribute: childAttr)
            for (i, child) in children.enumerated() {
                if i >= maxChildrenPerNode { break }
                if Date() >= deadline { return }
                collectText(from: child, depth: depth + 1, deadline: deadline, into: &output)
            }
        }
    }

    // MARK: - URL Extraction

    private func extractURL(appElement: AXUIElement, windowElement: AXUIElement?, bundleId: String?) -> String? {
        let browserBundles: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser", // Arc
            "company.thebrowser.dia", // Dia
            "org.mozilla.firefox",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
        ]
        guard let bid = bundleId, browserBundles.contains(bid) else { return nil }

        // Safari exposes kAXURLAttribute on the web content area
        if bid.contains("Safari") {
            if let window = windowElement, let url = findURLAttribute(in: window, depth: 0) {
                return url
            }
        }

        // Chromium-based browsers and Firefox: read the address bar value
        if let window = windowElement, let url = findAddressBar(in: window, depth: 0) {
            return url
        }

        return nil
    }

    /// Walk children looking for an element with kAXURLAttribute (Safari).
    private func findURLAttribute(in element: AXUIElement, depth: Int) -> String? {
        guard depth < 3 else { return nil }

        if let val = copyValue(from: element, attribute: kAXURLAttribute) {
            if let str = val as? String { return str }
            if let url = val as? URL { return url.absoluteString }
            if let cfStr = val as? NSURL { return cfStr.absoluteString }
        }

        for child in copyChildren(from: element, attribute: kAXChildrenAttribute).prefix(20) {
            if let url = findURLAttribute(in: child, depth: depth + 1) {
                return url
            }
        }
        return nil
    }

    /// Find the address bar in Chromium browsers by looking for AXTextField with relevant role description.
    private func findAddressBar(in element: AXUIElement, depth: Int) -> String? {
        guard depth < 6 else { return nil } // Chrome's tree is deeper

        let role = copyValue(from: element, attribute: kAXRoleAttribute) as? String
        let subrole = copyValue(from: element, attribute: kAXSubroleAttribute) as? String

        if role == "AXTextField" || subrole == "AXSearchField" {
            let roleDesc = (copyValue(from: element, attribute: kAXRoleDescriptionAttribute) as? String)?.lowercased() ?? ""
            if roleDesc.contains("address") || roleDesc.contains("search") || roleDesc.contains("url") {
                if let value = copyValue(from: element, attribute: kAXValueAttribute) as? String, !value.isEmpty {
                    return value
                }
            }
        }

        // Also check if the role description indicates this is a toolbar element
        if role == "AXToolbar" || role == "AXGroup" {
            for child in copyChildren(from: element, attribute: kAXChildrenAttribute).prefix(30) {
                if let url = findAddressBar(in: child, depth: depth + 1) {
                    return url
                }
            }
        } else {
            for child in copyChildren(from: element, attribute: kAXChildrenAttribute).prefix(15) {
                if let url = findAddressBar(in: child, depth: depth + 1) {
                    return url
                }
            }
        }
        return nil
    }

    // MARK: - AX Helpers

    private func copyElement(from element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard CFGetTypeID(value!) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func copyValue(from element: AXUIElement, attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func copyStringValue(from element: AXUIElement, attribute: String) -> String? {
        guard let value = copyValue(from: element, attribute: attribute) else { return nil }
        if let str = value as? String { return str }
        if let attr = value as? NSAttributedString { return attr.string }
        return nil
    }

    private func copyChildren(from element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }

    /// Batch-fetch multiple attributes in one IPC call.
    private func batchCopyValues(from element: AXUIElement, attributes: [String]) -> [Any] {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        guard error == .success, let results = values as? [Any] else { return [] }
        // Filter out NSError entries (failed attributes return errors with option 0)
        return results.filter { !($0 is NSError) }
    }

    /// Convert an AX value to a string, handling multiple possible types.
    private func flattenText(_ value: Any) -> String? {
        if let str = value as? String { return str }
        if let attr = value as? NSAttributedString { return attr.string }
        if let num = value as? NSNumber { return num.stringValue }
        if let strings = value as? [String] { return strings.joined(separator: " ") }
        if let array = value as? [Any] {
            let flattened = array.compactMap { flattenText($0) }
            return flattened.isEmpty ? nil : flattened.joined(separator: " ")
        }
        return nil
    }
}
