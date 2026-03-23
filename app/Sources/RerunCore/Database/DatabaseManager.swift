import Foundation
import GRDB
import CSQLiteVec

public actor DatabaseManager {
    private let dbPool: DatabasePool

    public init(path: String) throws {
        try self.init(path: path, extraPrepareDatabase: nil)
    }

    init(path: String, extraPrepareDatabase: (@Sendable (Database) throws -> Void)? = nil) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        var config = Configuration()
        config.foreignKeysEnabled = true
        config.maximumReaderCount = 5
        config.prepareDatabase { db in
            let rc = sqlite3_vec_init(db.sqliteConnection, nil, nil)
            guard rc == SQLITE_OK else {
                throw DatabaseError(message: "sqlite-vec init failed: \(rc)")
            }
            try extraPrepareDatabase?(db)
        }

        dbPool = try DatabasePool(path: path, configuration: config)
        try Self.migrator().migrate(dbPool)
    }

    /// Temporary database for testing. Creates a unique file in the temp directory.
    public init() throws {
        let path = NSTemporaryDirectory() + "rerun-test-\(UUID().uuidString).db"
        try self.init(path: path)
    }

    /// Default database path. Default profile: ~/Library/Application Support/Rerun/rerun.db
    public static func defaultPath(profile: String = RerunProfile.current()) throws -> String {
        let appSupport = RerunHome.appSupportURL(profile: profile)
        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        return RerunHome.databaseURL(profile: profile).path
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

        migrator.registerMigration("v1-captures-vec") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE captures_vec USING vec0(
                    capture_id TEXT PRIMARY KEY,
                    embedding FLOAT[512]
                )
                """)
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

    public func fetchCaptures(since: String?, limit: Int? = nil) throws -> [Capture] {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var request = Capture.order(Capture.Columns.timestamp.desc)
            if let normalizedSince {
                request = request.filter(sql: "timestamp >= ?", arguments: [normalizedSince])
            }
            if let limit {
                guard limit > 0 else { return [] }
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    public func fetchCaptures(app: String?, since: String?, limit: Int = 20) throws -> [Capture] {
        try fetchCaptures(apps: app.map { [$0] }, since: since, limit: limit)
    }

    public func fetchCaptures(apps: [String]?, since: String?, limit: Int = 20) throws -> [Capture] {
        try dbPool.read { db in
            guard limit > 0 else { return [] }
            let normalizedSince = canonicalSince(since)

            var request = Capture.order(Capture.Columns.timestamp.desc)
            if let apps, !apps.isEmpty {
                let placeholders = apps.map { _ in "?" }.joined(separator: ", ")
                request = request.filter(
                    sql: "appName COLLATE NOCASE IN (\(placeholders))",
                    arguments: StatementArguments(apps)
                )
            }
            if let normalizedSince {
                request = request.filter(sql: "timestamp >= ?", arguments: [normalizedSince])
            }

            return try request.limit(limit).fetchAll(db)
        }
    }

    public func fetchCapture(closestTo timestamp: String) throws -> Capture? {
        try dbPool.read { db in
            try Capture.fetchOne(db, sql: """
                SELECT * FROM capture
                ORDER BY ABS(julianday(timestamp) - julianday(?))
                LIMIT 1
                """, arguments: [timestamp])
        }
    }

    public func fetchCapture(id: String) throws -> Capture? {
        try dbPool.read { db in
            try Capture.fetchOne(db, id: id)
        }
    }

    public func captureCount() throws -> Int {
        try captureCount(since: nil)
    }

    public func captureCount(since: String?) throws -> Int {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var request = Capture.all()
            if let normalizedSince {
                request = request.filter(sql: "timestamp >= ?", arguments: [normalizedSince])
            }
            return try request.fetchCount(db)
        }
    }

    public func oldestCaptureTimestamp() throws -> String? {
        try oldestCaptureTimestamp(since: nil)
    }

    public func oldestCaptureTimestamp(since: String?) throws -> String? {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var request = Capture.order(Capture.Columns.timestamp.asc)
            if let normalizedSince {
                request = request.filter(sql: "timestamp >= ?", arguments: [normalizedSince])
            }
            return try request.limit(1).fetchOne(db)?.timestamp
        }
    }

    public func newestCaptureTimestamp() throws -> String? {
        try newestCaptureTimestamp(since: nil)
    }

    public func newestCaptureTimestamp(since: String?) throws -> String? {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var request = Capture.order(Capture.Columns.timestamp.desc)
            if let normalizedSince {
                request = request.filter(sql: "timestamp >= ?", arguments: [normalizedSince])
            }
            return try request.limit(1).fetchOne(db)?.timestamp
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
            guard limit > 0 else {
                return []
            }
            let normalizedSince = canonicalSince(since)

            guard let pattern = makeFTSQuery(query) else {
                return []
            }

            var sql = """
                SELECT capture.*
                FROM capture
                JOIN capture_fts ON capture_fts.rowid = capture.rowid
                    AND capture_fts MATCH \(sqlStringLiteral(pattern))
                """

            var conditions: [String] = []
            if let app {
                conditions.append("capture.appName = \(sqlStringLiteral(app)) COLLATE NOCASE")
            }
            if let normalizedSince {
                conditions.append("capture.timestamp >= \(sqlStringLiteral(normalizedSince))")
            }

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            sql += " ORDER BY rank LIMIT \(limit)"

            return try Capture.fetchAll(db, sql: sql)
        }
    }

    public func topApps(since: String? = nil, limit: Int = 10) throws -> [(appName: String, count: Int)] {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var sql = "SELECT appName, COUNT(*) as cnt FROM capture"
            var arguments: [any DatabaseValueConvertible] = []
            if let normalizedSince {
                sql += " WHERE timestamp >= ?"
                arguments.append(normalizedSince)
            }
            sql += " GROUP BY appName ORDER BY cnt DESC LIMIT ?"
            arguments.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.map { ($0["appName"] as String, $0["cnt"] as Int) }
        }
    }

    public func topURLs(since: String? = nil, limit: Int = 10) throws -> [(url: String, count: Int)] {
        try dbPool.read { db in
            let normalizedSince = canonicalSince(since)
            var sql = "SELECT url, COUNT(*) as cnt FROM capture WHERE url IS NOT NULL"
            var arguments: [any DatabaseValueConvertible] = []
            if let normalizedSince {
                sql += " AND timestamp >= ?"
                arguments.append(normalizedSince)
            }
            sql += " GROUP BY url ORDER BY cnt DESC LIMIT ?"
            arguments.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.map { ($0["url"] as String, $0["cnt"] as Int) }
        }
    }

    // MARK: - Ranked Search (for hybrid scoring)

    public func searchCapturesWithRank(
        query: String,
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20
    ) throws -> [(capture: Capture, rank: Float)] {
        try dbPool.read { db in
            guard limit > 0 else { return [] }
            let normalizedSince = canonicalSince(since)
            guard let pattern = makeFTSQuery(query) else { return [] }

            var sql = """
                SELECT capture.*, rank
                FROM capture
                JOIN capture_fts ON capture_fts.rowid = capture.rowid
                    AND capture_fts MATCH \(sqlStringLiteral(pattern))
                """

            var conditions: [String] = []
            if let app {
                conditions.append("capture.appName = \(sqlStringLiteral(app)) COLLATE NOCASE")
            }
            if let normalizedSince {
                conditions.append("capture.timestamp >= \(sqlStringLiteral(normalizedSince))")
            }
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            sql += " ORDER BY rank LIMIT \(limit)"

            let rows = try Row.fetchAll(db, sql: sql)
            return try rows.map { row in
                let capture = try Capture(row: row)
                let rank: Float = row["rank"]
                return (capture: capture, rank: rank)
            }
        }
    }

    public func substringSearchCaptures(
        query: String,
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20
    ) throws -> [Capture] {
        try dbPool.read { db in
            guard limit > 0 else { return [] }
            let normalizedSince = canonicalSince(since)
            let terms = query
                .split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }
            guard !terms.isEmpty else { return [] }

            var conditions: [String] = []
            if let app {
                conditions.append("appName = \(sqlStringLiteral(app)) COLLATE NOCASE")
            }
            if let normalizedSince {
                conditions.append("timestamp >= \(sqlStringLiteral(normalizedSince))")
            }

            let termConditions = terms.map { term in
                let pattern = sqlLikeLiteral(term)
                return """
                    lower(textContent) LIKE \(pattern) ESCAPE '\\'
                    OR lower(COALESCE(windowTitle, '')) LIKE \(pattern) ESCAPE '\\'
                    OR lower(COALESCE(url, '')) LIKE \(pattern) ESCAPE '\\'
                    OR lower(appName) LIKE \(pattern) ESCAPE '\\'
                    """
            }
            conditions.append("(" + termConditions.joined(separator: " OR ") + ")")

            let sql = """
                SELECT *
                FROM capture
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY timestamp DESC
                LIMIT \(limit)
                """

            return try Capture.fetchAll(db, sql: sql)
        }
    }

    private func makeFTSQuery(_ query: String) -> String? {
        let allowedSymbols = CharacterSet(charactersIn: "+#./-_")
        let normalized = query.precomposedStringWithCompatibilityMapping
        let terms = normalized
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.unicodeScalars.map { scalar -> Character in
                    if CharacterSet.alphanumerics.contains(scalar) || allowedSymbols.contains(scalar) {
                        return Character(scalar)
                    }
                    return " "
                }
            }
            .map { String($0).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return nil }

        return terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    public func findSimilarWithDistance(
        to embedding: [Float],
        app: String? = nil,
        since: String? = nil,
        limit: Int = 20
    ) throws -> [(capture: Capture, distance: Float)] {
        try dbPool.read { db in
            guard limit > 0 else { return [] }
            let normalizedSince = canonicalSince(since)
            let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            let rowCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM captures_vec") ?? 0
            guard rowCount > 0 else { return [] }
            let candidateLimit: Int
            if app == nil && normalizedSince == nil {
                candidateLimit = min(limit * 3, rowCount)
            } else {
                // sqlite-vec can't push outer filters into the KNN query, so filtered
                // searches need the full candidate set to avoid dropping valid matches.
                candidateLimit = rowCount
            }

            var sql = """
                SELECT capture.*, vec.distance
                FROM (
                    SELECT capture_id, distance
                    FROM captures_vec
                    WHERE embedding MATCH :embedding AND k = :candidateLimit
                    ORDER BY distance
                ) AS vec
                JOIN capture ON capture.id = vec.capture_id
                """
            var arguments: [String: (any DatabaseValueConvertible)?] = [
                "embedding": blob,
                "candidateLimit": candidateLimit,
            ]

            var conditions: [String] = []
            if let app {
                conditions.append("capture.appName = :app COLLATE NOCASE")
                arguments["app"] = app
            }
            if let normalizedSince {
                conditions.append("capture.timestamp >= :since")
                arguments["since"] = normalizedSince
            }
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            sql += " ORDER BY vec.distance LIMIT :limit"
            arguments["limit"] = limit

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return try rows.map { row in
                let capture = try Capture(row: row)
                let distance: Float = row["distance"]
                return (capture: capture, distance: distance)
            }
        }
    }

    private func canonicalSince(_ since: String?) -> String? {
        guard let since else { return nil }
        return SearchTimeParser.parseSince(since) ?? since
    }

    private func sqlStringLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func sqlLikeLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "'", with: "''")
        return "'%" + escaped + "%'"
    }

    // MARK: - Vector Embeddings

    public func insertEmbedding(captureId: String, embedding: [Float]) throws {
        try dbPool.write { db in
            let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            try db.execute(
                sql: "INSERT INTO captures_vec(capture_id, embedding) VALUES (?, ?)",
                arguments: [captureId, blob]
            )
        }
    }

    public func findSimilar(to embedding: [Float], limit: Int = 20) throws -> [(captureId: String, distance: Float)] {
        try dbPool.read { db in
            let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            let rows = try Row.fetchAll(db, sql: """
                SELECT capture_id, distance
                FROM captures_vec
                WHERE embedding MATCH ? AND k = ?
                ORDER BY distance
                """, arguments: [blob, limit])
            return rows.map { ($0["capture_id"], $0["distance"]) }
        }
    }

    public func findSimilarCaptures(to embedding: [Float], limit: Int = 20) throws -> [Capture] {
        try dbPool.read { db in
            let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            return try Capture.fetchAll(db, sql: """
                SELECT capture.*
                FROM (
                    SELECT capture_id, distance
                    FROM captures_vec
                    WHERE embedding MATCH ? AND k = ?
                    ORDER BY distance
                ) AS vec
                JOIN capture ON capture.id = vec.capture_id
                ORDER BY vec.distance
                """, arguments: [blob, limit])
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
