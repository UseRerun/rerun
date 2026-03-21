import Foundation

public struct SearchResult: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?
    public let url: String?
    public let snippet: String
    public let textSource: String

    public init(capture: Capture, snippet: String) {
        self.id = capture.id
        self.timestamp = capture.timestamp
        self.appName = capture.appName
        self.bundleId = capture.bundleId
        self.windowTitle = capture.windowTitle
        self.url = capture.url
        self.snippet = snippet
        self.textSource = capture.textSource
    }

    /// Extract a snippet of text centered on the first occurrence of a query word.
    public static func makeSnippet(from text: String, query: String, maxLength: Int = 200) -> String {
        let lower = text.lowercased()
        let queryWords = query.lowercased().split(separator: " ")

        // Find the first occurrence of any query word
        var bestIndex = text.startIndex
        for word in queryWords {
            if let range = lower.range(of: word) {
                bestIndex = range.lowerBound
                break
            }
        }

        // Expand a window around the match
        let half = maxLength / 2
        let start = text.index(bestIndex, offsetBy: -half, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(bestIndex, offsetBy: half, limitedBy: text.endIndex) ?? text.endIndex

        var snippet = String(text[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if start > text.startIndex { snippet = "..." + snippet }
        if end < text.endIndex { snippet = snippet + "..." }

        return snippet
    }
}
