import Foundation
import GRDB

public struct Summary: Codable, Identifiable, Sendable {
    public var id: String
    public var periodType: String
    public var periodStart: String
    public var periodEnd: String
    public var summaryText: String
    public var topics: String?
    public var appsUsed: String?
    public var urlsVisited: String?
    public var markdownPath: String?
    public var createdAt: String

    public init(
        id: String = UUID().uuidString,
        periodType: String,
        periodStart: String,
        periodEnd: String,
        summaryText: String,
        topics: String? = nil,
        appsUsed: String? = nil,
        urlsVisited: String? = nil,
        markdownPath: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.summaryText = summaryText
        self.topics = topics
        self.appsUsed = appsUsed
        self.urlsVisited = urlsVisited
        self.markdownPath = markdownPath
        self.createdAt = createdAt ?? ISO8601DateFormatter().string(from: Date())
    }
}

extension Summary: FetchableRecord, PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let periodType = Column(CodingKeys.periodType)
        public static let periodStart = Column(CodingKeys.periodStart)
        public static let periodEnd = Column(CodingKeys.periodEnd)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
