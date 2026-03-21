import Foundation

enum MessageRole: Sendable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let sources: [SourceReference]
    let timestamp: Date

    init(role: MessageRole, content: String, sources: [SourceReference] = [], timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.sources = sources
        self.timestamp = timestamp
    }
}

struct SourceReference: Sendable {
    let captureId: String
    let appName: String
    let timestamp: String
    let windowTitle: String?
    let url: String?
    let snippet: String
}
