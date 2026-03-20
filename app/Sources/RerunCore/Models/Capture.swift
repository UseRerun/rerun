import Foundation
import GRDB

public struct Capture: Codable, Identifiable, Sendable {
    public var id: String
    public var timestamp: String
    public var appName: String
    public var bundleId: String?
    public var windowTitle: String?
    public var url: String?
    public var textSource: String
    public var captureTrigger: String
    public var textContent: String
    public var textHash: String
    public var displayId: String?
    public var isFrontmost: Bool
    public var markdownPath: String?
    public var createdAt: String

    public init(
        id: String = UUID().uuidString,
        timestamp: String,
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        textSource: String,
        captureTrigger: String,
        textContent: String,
        textHash: String,
        displayId: String? = nil,
        isFrontmost: Bool = true,
        markdownPath: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.textSource = textSource
        self.captureTrigger = captureTrigger
        self.textContent = textContent
        self.textHash = textHash
        self.displayId = displayId
        self.isFrontmost = isFrontmost
        self.markdownPath = markdownPath
        self.createdAt = createdAt ?? ISO8601DateFormatter().string(from: Date())
    }
}

extension Capture: FetchableRecord, PersistableRecord {
    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let timestamp = Column(CodingKeys.timestamp)
        public static let appName = Column(CodingKeys.appName)
        public static let bundleId = Column(CodingKeys.bundleId)
        public static let windowTitle = Column(CodingKeys.windowTitle)
        public static let url = Column(CodingKeys.url)
        public static let textSource = Column(CodingKeys.textSource)
        public static let captureTrigger = Column(CodingKeys.captureTrigger)
        public static let textContent = Column(CodingKeys.textContent)
        public static let textHash = Column(CodingKeys.textHash)
        public static let displayId = Column(CodingKeys.displayId)
        public static let isFrontmost = Column(CodingKeys.isFrontmost)
        public static let markdownPath = Column(CodingKeys.markdownPath)
        public static let createdAt = Column(CodingKeys.createdAt)
    }
}
