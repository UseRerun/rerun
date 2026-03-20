import Foundation
import GRDB

public struct Exclusion: Codable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var value: String
    public var createdAt: String

    public init(
        id: String = UUID().uuidString,
        type: String,
        value: String,
        createdAt: String? = nil
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.createdAt = createdAt ?? ISO8601DateFormatter().string(from: Date())
    }
}

extension Exclusion: FetchableRecord, PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let type = Column(CodingKeys.type)
        public static let value = Column(CodingKeys.value)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
