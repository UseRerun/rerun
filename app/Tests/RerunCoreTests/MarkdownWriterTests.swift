import Testing
import Foundation
@testable import RerunCore

@Suite("MarkdownWriter")
struct MarkdownWriterTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rerun-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeCapture(
        timestamp: String? = nil,
        appName: String = "Safari",
        bundleId: String? = "com.apple.Safari",
        windowTitle: String? = "Stripe API Reference",
        url: String? = "https://stripe.com/docs/api/charges",
        textContent: String = "Stripe API charges endpoint POST /v1/charges"
    ) -> Capture {
        Capture(
            timestamp: timestamp ?? ISO8601DateFormatter().string(from: Date()),
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            textSource: "accessibility",
            captureTrigger: "app_switch",
            textContent: textContent,
            textHash: UUID().uuidString
        )
    }

    @Test func writeBasicCapture() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = MarkdownWriter(baseURL: dir)
        let capture = makeCapture()
        let path = try writer.write(capture)

        let fileURL = dir.appendingPathComponent(path)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.hasPrefix("---\n"))
        #expect(content.contains("id: \(capture.id)"))
        #expect(content.contains("timestamp: \(capture.timestamp)"))
        #expect(content.contains("app: Safari"))
        #expect(content.contains("bundle_id: com.apple.Safari"))
        #expect(content.contains("window: \"Stripe API Reference\""))
        #expect(content.contains("url: https://stripe.com/docs/api/charges"))
        #expect(content.contains("source: accessibility"))
        #expect(content.contains("trigger: app_switch"))
        #expect(content.contains("---\n\nStripe API charges endpoint"))
    }

    @Test func collisionHandling() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = MarkdownWriter(baseURL: dir)
        let ts = ISO8601DateFormatter().string(from: Date())

        let path1 = try writer.write(makeCapture(timestamp: ts, textContent: "first"))
        let path2 = try writer.write(makeCapture(timestamp: ts, textContent: "second"))

        #expect(path1.hasSuffix(".md"))
        #expect(path2.hasSuffix("-2.md"))
        #expect(path1 != path2)

        let content1 = try String(contentsOf: dir.appendingPathComponent(path1), encoding: .utf8)
        let content2 = try String(contentsOf: dir.appendingPathComponent(path2), encoding: .utf8)
        #expect(content1.contains("first"))
        #expect(content2.contains("second"))
    }

    @Test func optionalFieldsOmitted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = MarkdownWriter(baseURL: dir)
        let capture = makeCapture(bundleId: nil, windowTitle: nil, url: nil)
        let path = try writer.write(capture)

        let content = try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
        #expect(!content.contains("bundle_id:"))
        #expect(!content.contains("window:"))
        #expect(!content.contains("url:"))
        #expect(content.contains("app: Safari"))
        #expect(content.contains("source: accessibility"))
    }

    @Test func windowTitleEscaping() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = MarkdownWriter(baseURL: dir)
        let capture = makeCapture(windowTitle: "API: \"Create Charge\"")
        let path = try writer.write(capture)

        let content = try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
        #expect(content.contains("window: \"API: \\\"Create Charge\\\"\""))
    }

    @Test func relativePathFormat() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = MarkdownWriter(baseURL: dir)
        let path = try writer.write(makeCapture())

        #expect(path.hasPrefix("captures/"))
        #expect(path.hasSuffix(".md"))
        #expect(!path.hasPrefix("/"))
    }
}
