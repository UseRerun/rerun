import Foundation

enum MessageRole: Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let sources: [SourceReference]
    let summaryDebug: SummaryDebugInfo?
    let timestamp: Date

    init(
        role: MessageRole,
        content: String,
        sources: [SourceReference] = [],
        summaryDebug: SummaryDebugInfo? = nil,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.sources = sources
        self.summaryDebug = summaryDebug
        self.timestamp = timestamp
    }
}

struct SourceReference: Identifiable, Sendable {
    var id: String { captureId }
    let captureId: String
    let appName: String
    let timestamp: String
    let windowTitle: String?
    let url: String?
    let snippet: String
}

struct SummaryDebugInfo: Sendable {
    let appFilter: String?
    let appSummary: [String]
    let workspaces: [String]
    let facts: [String]
}
