import RerunCore
import Foundation
import AppKit

// Quick AX diagnostic if --test-ax flag is passed
if CommandLine.arguments.contains("--test-ax") {
    print("Accessibility granted: \(AccessibilityExtractor.isAccessibilityGranted)")

    let extractor = AccessibilityExtractor()
    if let result = extractor.extract() {
        print("App: \(result.appName)")
        print("Bundle ID: \(result.bundleId ?? "nil")")
        print("Window: \(result.windowTitle ?? "nil")")
        print("URL: \(result.url ?? "nil")")
        print("Source: \(result.source.rawValue)")
        print("Needs OCR: \(result.needsOCRFallback)")
        print("Text length: \(result.text.count) chars")
        if !result.text.isEmpty {
            print("Text preview: \(String(result.text.prefix(500)))")
        }
    } else {
        print("No result (no focused window or no permission)")
    }
    exit(0)
}

print("Rerun daemon v\(Rerun.version) starting...")
print("Press Ctrl+C to stop.")

// Keep the daemon alive
RunLoop.main.run()
