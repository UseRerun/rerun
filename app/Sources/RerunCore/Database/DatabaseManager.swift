import Foundation
import GRDB

public actor DatabaseManager {
    private let dbPool: DatabasePool

    public init(path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        var config = Configuration()
        config.foreignKeysEnabled = true
        config.maximumReaderCount = 5

        dbPool = try DatabasePool(path: path, configuration: config)
        try Self.migrator().migrate(dbPool)
    }

    /// Temporary database for testing. Creates a unique file in the temp directory.
    public init() throws {
        let path = NSTemporaryDirectory() + "rerun-test-\(UUID().uuidString).db"
        try self.init(path: path)
    }

    /// Default database path: ~/Library/Application Support/Rerun/rerun.db
    public static func defaultPath() throws -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Rerun", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        return appSupport.appendingPathComponent("rerun.db").path
    }

    // MARK: - Migrations

    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1-captures") { db in
            try db.create(table: "capture") { t in
                t.primaryKey("id", .text)
                t.column("timestamp", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("bundleId", .text)
                t.column("windowTitle", .text)
                t.column("url", .text)
                t.column("textSource", .text).notNull()
                t.column("captureTrigger", .text).notNull()
                t.column("textContent", .text).notNull()
                t.column("textHash", .text).notNull()
                t.column("displayId", .text)
                t.column("isFrontmost", .boolean).defaults(to: true)
                t.column("markdownPath", .text)
                t.column("createdAt", .text).notNull()
            }

            try db.create(index: "idx_capture_timestamp", on: "capture", columns: ["timestamp"])
            try db.create(index: "idx_capture_appName", on: "capture", columns: ["appName"])
            try db.create(index: "idx_capture_textHash", on: "capture", columns: ["textHash"])
        }

        migrator.registerMigration("v1-captures-fts") { db in
            try db.create(virtualTable: "capture_fts", using: FTS5()) { t in
                t.synchronize(withTable: "capture")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("textContent")
                t.column("appName")
                t.column("windowTitle")
                t.column("url")
            }
        }

        migrator.registerMigration("v1-summaries") { db in
            try db.create(table: "summary") { t in
                t.primaryKey("id", .text)
                t.column("periodType", .text).notNull()
                t.column("periodStart", .text).notNull()
                t.column("periodEnd", .text).notNull()
                t.column("summaryText", .text).notNull()
                t.column("topics", .text)
                t.column("appsUsed", .text)
                t.column("urlsVisited", .text)
                t.column("markdownPath", .text)
                t.column("createdAt", .text).notNull()
            }

            try db.create(
                index: "idx_summary_period",
                on: "summary",
                columns: ["periodType", "periodStart"]
            )
        }

        migrator.registerMigration("v1-exclusions") { db in
            try db.create(table: "exclusion") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("value", .text).notNull()
                t.column("createdAt", .text).notNull()
            }

            try db.create(
                index: "idx_exclusion_type_value",
                on: "exclusion",
                columns: ["type", "value"],
                unique: true
            )
        }

        return migrator
    }

    // MARK: - Captures

    public func insertCapture(_ capture: Capture) throws {
        try dbPool.write { db in
            try capture.insert(db)
        }
    }

    public func fetchCaptures(limit: Int = 20) throws -> [Capture] {
        try dbPool.read { db in
            try Capture
                .order(Capture.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func fetchCapture(id: String) throws -> Capture? {
        try dbPool.read { db in
            try Capture.fetchOne(db, id: id)
        }
    }

    public func captureCount() throws -> Int {
        try dbPool.read { db in
            try Capture.fetchCount(db)
        }
    }

    public func latestHashForApp(_ appName: String) throws -> String? {
        try dbPool.read { db in
            try Capture
                .filter(Capture.Columns.appName == appName)
                .order(Capture.Columns.timestamp.desc)
                .limit(1)
                .fetchOne(db)?
                .textHash
        }
    }

    public func searchCaptures(
        query: String,
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20
    ) throws -> [Capture] {
        try dbPool.read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
                return []
            }

            var sql = """
                SELECT capture.*
                FROM capture
                JOIN capture_fts ON capture_fts.rowid = capture.rowid
                    AND capture_fts MATCH ?
                """
            var arguments: [any DatabaseValueConvertible] = [pattern]

            var conditions: [String] = []
            if let app {
                conditions.append("capture.appName = ?")
                arguments.append(app)
            }
            if let since {
                conditions.append("capture.timestamp >= ?")
                arguments.append(since)
            }

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            sql += " ORDER BY rank LIMIT ?"
            arguments.append(limit)

            return try Capture.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    // MARK: - Summaries

    public func insertSummary(_ summary: Summary) throws {
        try dbPool.write { db in
            try summary.insert(db)
        }
    }

    public func fetchSummaries(periodType: String, limit: Int = 20) throws -> [Summary] {
        try dbPool.read { db in
            try Summary
                .filter(Summary.Columns.periodType == periodType)
                .order(Summary.Columns.periodStart.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Exclusions

    public func insertExclusion(_ exclusion: Exclusion) throws {
        try dbPool.write { db in
            try exclusion.insert(db)
        }
    }

    public func fetchExclusions() throws -> [Exclusion] {
        try dbPool.read { db in
            try Exclusion.fetchAll(db)
        }
    }

    public func deleteExclusion(id: String) throws -> Bool {
        try dbPool.write { db in
            try Exclusion.deleteOne(db, id: id)
        }
    }

    public func exclusionExists(type: String, value: String) throws -> Bool {
        try dbPool.read { db in
            try Exclusion
                .filter(Exclusion.Columns.type == type && Exclusion.Columns.value == value)
                .fetchCount(db) > 0
        }
    }
}
