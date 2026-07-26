import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SearchDatabase {
    private var database: OpaquePointer?
    private nonisolated let reader: SearchDatabaseReader

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw DatabaseError(message)
        }
        database = handle

        try Self.execute("PRAGMA journal_mode = WAL", on: handle)
        try Self.execute("PRAGMA synchronous = NORMAL", on: handle)
        try Self.execute("""
            CREATE TABLE IF NOT EXISTS items (
                path TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                kind INTEGER NOT NULL,
                bundle_identifier TEXT,
                modified_at REAL,
                file_size INTEGER,
                generation INTEGER NOT NULL
            )
            """, on: handle)
        try Self.ensureColumn(
            named: "file_size",
            definition: "INTEGER",
            in: "items",
            database: handle
        )
        try Self.execute("CREATE INDEX IF NOT EXISTS items_normalized_name ON items(normalized_name)", on: handle)
        try Self.execute(
            "CREATE INDEX IF NOT EXISTS items_kind_modified_at ON items(kind, modified_at DESC)",
            on: handle
        )
        try Self.execute(
            """
            CREATE INDEX IF NOT EXISTS items_kind_file_size_modified_at
            ON items(kind, file_size DESC, modified_at DESC)
            """,
            on: handle
        )
        try Self.execute("""
            CREATE TABLE IF NOT EXISTS usage (
                path TEXT PRIMARY KEY,
                launch_count INTEGER NOT NULL DEFAULT 0,
                last_launched REAL
            )
            """, on: handle)
        try Self.execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """, on: handle)
        reader = try SearchDatabaseReader(url: url)
    }

    deinit {
        sqlite3_close(database)
    }

    func beginIndex(generation: Int64) throws {
        try setMetadata(key: "active_generation", value: String(generation))
    }

    func upsert(_ items: [IndexedItem], generation: Int64) throws {
        guard !items.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        let sql = """
            INSERT INTO items(
                path, name, normalized_name, kind, bundle_identifier,
                modified_at, file_size, generation
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                normalized_name = excluded.normalized_name,
                kind = excluded.kind,
                bundle_identifier = excluded.bundle_identifier,
                modified_at = excluded.modified_at,
                file_size = excluded.file_size,
                generation = excluded.generation
            """
        do {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            for item in items {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(item.path, at: 1, to: statement)
                bind(item.name, at: 2, to: statement)
                bind(item.normalizedName, at: 3, to: statement)
                sqlite3_bind_int(statement, 4, Int32(item.kind.rawValue))
                bind(item.bundleIdentifier, at: 5, to: statement)
                if let modifiedAt = item.modifiedAt {
                    sqlite3_bind_double(statement, 6, modifiedAt)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                if let fileSize = item.fileSize {
                    sqlite3_bind_int64(statement, 7, fileSize)
                } else {
                    sqlite3_bind_null(statement, 7)
                }
                sqlite3_bind_int64(statement, 8, generation)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw lastError()
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func finishIndex(generation: Int64) throws {
        do {
            try execute("BEGIN IMMEDIATE")
            let statement = try prepare("DELETE FROM items WHERE generation != ?")
            sqlite3_bind_int64(statement, 1, generation)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                throw lastError()
            }
            sqlite3_finalize(statement)
            try setMetadata(key: "last_indexed_at", value: String(Date().timeIntervalSince1970))
            try setMetadata(key: "index_schema_version", value: "2")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func cancelIndex() {
        // Each batch is committed independently so a cancelled or failed scan
        // still leaves a useful partial index. Stale entries are only removed
        // after a complete scan.
    }

    func _testOnlyHoldWriter(
        milliseconds: Int,
        started: @Sendable () -> Void
    ) {
        started()
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
    }

    func currentGeneration() throws -> Int64 {
        let statement = try prepare(
            "SELECT value FROM metadata WHERE key = 'active_generation'"
        )
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) == SQLITE_ROW,
           let value = sqlite3_column_text(statement, 0),
           let generation = Int64(String(cString: value)) {
            return generation
        }
        let generation = Int64(Date().timeIntervalSince1970 * 1_000)
        try setMetadata(key: "active_generation", value: String(generation))
        return generation
    }

    func lastFileSystemEventID() throws -> UInt64? {
        let statement = try prepare(
            "SELECT value FROM metadata WHERE key = 'last_filesystem_event_id'"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return UInt64(String(cString: value))
    }

    func setLastFileSystemEventID(_ eventID: UInt64) throws {
        try setMetadata(key: "last_filesystem_event_id", value: String(eventID))
    }

    func remove(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            let exactStatement = try prepare("DELETE FROM items WHERE path = ?")
            defer { sqlite3_finalize(exactStatement) }
            let descendantsStatement = try prepare("""
                DELETE FROM items
                WHERE path >= ? AND path < ?
                """)
            defer { sqlite3_finalize(descendantsStatement) }
            for path in paths {
                sqlite3_reset(exactStatement)
                sqlite3_clear_bindings(exactStatement)
                bind(path, at: 1, to: exactStatement)
                guard sqlite3_step(exactStatement) == SQLITE_DONE else {
                    throw lastError()
                }

                let descendantPrefix = path + "/"
                sqlite3_reset(descendantsStatement)
                sqlite3_clear_bindings(descendantsStatement)
                bind(descendantPrefix, at: 1, to: descendantsStatement)
                bind(descendantPrefix + "\u{10FFFF}", at: 2, to: descendantsStatement)
                guard sqlite3_step(descendantsStatement) == SQLITE_DONE else {
                    throw lastError()
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    nonisolated func search(
        query rawQuery: String,
        includeFilesAndFolders: Bool = true,
        preferApplications: Bool = true,
        limit: Int = 30
    ) async throws -> [SearchResult] {
        try await reader.search(
            query: rawQuery,
            includeFilesAndFolders: includeFilesAndFolders,
            preferApplications: preferApplications,
            limit: limit
        )
    }

    nonisolated func browseLargeFiles(
        filter rawFilter: String,
        limit: Int = 100
    ) async throws -> [SearchResult] {
        try await reader.browseLargeFiles(filter: rawFilter, limit: limit)
    }

    nonisolated func browseRecentFiles(
        filter rawFilter: String,
        preferUserDirectories: Bool = false,
        homeDirectory: String = NSHomeDirectory(),
        limit: Int = 100
    ) async throws -> [SearchResult] {
        try await reader.browseRecentFiles(
            filter: rawFilter,
            preferUserDirectories: preferUserDirectories,
            homeDirectory: homeDirectory,
            limit: limit
        )
    }

    func recordLaunch(path: String) throws {
        let statement = try prepare("""
            INSERT INTO usage(path, launch_count, last_launched)
            VALUES(?, 1, ?)
            ON CONFLICT(path) DO UPDATE SET
                launch_count = launch_count + 1,
                last_launched = excluded.last_launched
            """)
        defer { sqlite3_finalize(statement) }
        bind(path, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }

    func indexedItemCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM items")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func indexNeedsUpgrade() throws -> Bool {
        let statement = try prepare(
            "SELECT value FROM metadata WHERE key = 'index_schema_version'"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return true
        }
        return Int(String(cString: value)) ?? 0 < 2
    }

    private func setMetadata(key: String, value: String) throws {
        let statement = try prepare("""
            INSERT INTO metadata(key, value) VALUES(?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """)
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, to: statement)
        bind(value, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func browseFiles(
        filter rawFilter: String,
        orderBy: String,
        requireSize: Bool,
        additionalScope: String,
        limit: Int
    ) throws -> [SearchResult] {
        let filter = Self.normalize(rawFilter.trimmingCharacters(in: .whitespacesAndNewlines))
        let sizeClause = requireSize ? "AND i.file_size IS NOT NULL" : ""
        let sql: String
        if filter.isEmpty {
            sql = """
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM items i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.kind = 0
                  \(sizeClause)
                  AND i.path NOT LIKE '%/Library/Application Support/CmdSpace/%'
                  \(additionalScope)
                ORDER BY \(orderBy)
                LIMIT ?
                """
        } else {
            sql = """
                WITH candidates AS MATERIALIZED (
                    SELECT i.path, i.name, i.normalized_name, i.kind,
                           i.modified_at, i.file_size
                    FROM items i
                    WHERE i.kind = 0
                      \(sizeClause)
                      AND i.path NOT LIKE '%/Library/Application Support/CmdSpace/%'
                      \(additionalScope)
                    ORDER BY \(orderBy)
                    LIMIT ?
                )
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM candidates i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.normalized_name LIKE ? ESCAPE '\\'
                ORDER BY \(orderBy)
                LIMIT ?
                """
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if !filter.isEmpty {
            let candidateLimit = max(limit * 10, 10_000)
            sqlite3_bind_int(statement, bindIndex, Int32(candidateLimit))
            bindIndex += 1
            bind("%\(escapeLike(filter))%", at: bindIndex, to: statement)
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var results: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0),
                  let nameText = sqlite3_column_text(statement, 1) else { continue }
            let lastLaunched = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let modifiedAt = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let fileSize = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 6)
            results.append(SearchResult(
                path: String(cString: pathText),
                name: String(cString: nameText),
                kind: .file,
                launchCount: Int(sqlite3_column_int(statement, 3)),
                lastLaunched: lastLaunched,
                modifiedAt: modifiedAt,
                fileSize: fileSize,
                score: 0
            ))
        }
        return results
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw lastError()
        }
    }

    private static func execute(_ sql: String, on database: OpaquePointer?) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Database unavailable"
            throw DatabaseError(message)
        }
    }

    private static func ensureColumn(
        named column: String,
        definition: String,
        in table: String,
        database: OpaquePointer?
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil)
                == SQLITE_OK,
              let statement else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Database unavailable"
            throw DatabaseError(message)
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1),
               String(cString: name) == column {
                return
            }
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)", on: database)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw lastError()
        }
        return statement
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func lastError() -> DatabaseError {
        DatabaseError(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable")
    }

    private func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
    }
}

private actor SearchDatabaseReader {
    private var database: OpaquePointer?

    init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Database unavailable"
            sqlite3_close(handle)
            throw DatabaseError(message)
        }
        database = handle
        guard sqlite3_exec(handle, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError(String(cString: sqlite3_errmsg(handle)))
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func search(
        query rawQuery: String,
        includeFilesAndFolders: Bool,
        preferApplications: Bool,
        limit: Int
    ) throws -> [SearchResult] {
        let query = SearchDatabase.normalize(
            rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let sql: String
        if query.isEmpty {
            sql = """
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM items i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.kind = 2
                ORDER BY COALESCE(u.last_launched, 0) DESC,
                         COALESCE(u.launch_count, 0) DESC, i.name
                LIMIT 250
                """
        } else {
            let kindFilter = includeFilesAndFolders ? "" : "AND i.kind = 2"
            let applicationOrdering = preferApplications
                ? "ORDER BY CASE WHEN i.kind = 2 THEN 0 ELSE 1 END"
                : ""
            sql = """
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM items i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.normalized_name LIKE ? ESCAPE '\\'
                \(kindFilter)
                \(applicationOrdering)
                LIMIT 500
                """
        }

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if !query.isEmpty {
            bind("%\(escapeLike(query))%", at: 1, to: statement)
        }

        var results: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0),
                  let nameText = sqlite3_column_text(statement, 1) else {
                continue
            }
            let path = String(cString: pathText)
            let name = String(cString: nameText)
            let kind = ItemKind(rawValue: Int(sqlite3_column_int(statement, 2))) ?? .file
            let launchCount = Int(sqlite3_column_int(statement, 3))
            let lastLaunched: Date? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let modifiedAt: Date? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let fileSize: Int64? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 6)
            results.append(SearchResult(
                path: path,
                name: name,
                kind: kind,
                launchCount: launchCount,
                lastLaunched: lastLaunched,
                modifiedAt: modifiedAt,
                fileSize: fileSize,
                score: SearchRanker.score(
                    query: query,
                    name: name,
                    launchCount: launchCount,
                    lastLaunched: lastLaunched
                )
            ))
        }

        return results.sorted {
            let lhsIsApplication = $0.kind == .application
            let rhsIsApplication = $1.kind == .application
            if preferApplications, lhsIsApplication != rhsIsApplication {
                return lhsIsApplication
            }
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.kind != $1.kind { return $0.kind.rawValue > $1.kind.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.prefix(limit).map { $0 }
    }

    func browseLargeFiles(filter: String, limit: Int) throws -> [SearchResult] {
        try browseFiles(
            filter: filter,
            orderBy: "i.file_size DESC, i.modified_at DESC",
            requireSize: true,
            additionalScope: "",
            limit: limit
        )
    }

    func browseRecentFiles(
        filter: String,
        preferUserDirectories: Bool,
        homeDirectory: String,
        limit: Int
    ) throws -> [SearchResult] {
        let preferredDirectories = [
            "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"
        ].map {
            (homeDirectory as NSString).appendingPathComponent($0) + "/"
        }
        let candidateLimit = preferUserDirectories ? max(limit * 3, 1_000) : limit
        let candidates = try browseFiles(
            filter: filter,
            orderBy: "i.modified_at DESC, i.name COLLATE NOCASE",
            requireSize: false,
            additionalScope: """
                AND i.path LIKE '/Users/%'
                AND i.path NOT LIKE '/Users/%/Library/%'
                """,
            limit: candidateLimit
        )
        guard preferUserDirectories else { return candidates }

        let preferred = candidates.filter { result in
            preferredDirectories.contains { result.path.hasPrefix($0) }
        }
        let other = candidates.filter { result in
            !preferredDirectories.contains { result.path.hasPrefix($0) }
        }
        return Array((preferred + other).prefix(limit))
    }

    private func browseFiles(
        filter rawFilter: String,
        orderBy: String,
        requireSize: Bool,
        additionalScope: String,
        limit: Int
    ) throws -> [SearchResult] {
        let filter = SearchDatabase.normalize(
            rawFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let sizeClause = requireSize ? "AND i.file_size IS NOT NULL" : ""
        let sql: String
        if filter.isEmpty {
            sql = """
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM items i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.kind = 0
                  \(sizeClause)
                  AND i.path NOT LIKE '%/Library/Application Support/CmdSpace/%'
                  \(additionalScope)
                ORDER BY \(orderBy)
                LIMIT ?
                """
        } else {
            sql = """
                WITH candidates AS MATERIALIZED (
                    SELECT i.path, i.name, i.normalized_name, i.kind,
                           i.modified_at, i.file_size
                    FROM items i
                    WHERE i.kind = 0
                      \(sizeClause)
                      AND i.path NOT LIKE '%/Library/Application Support/CmdSpace/%'
                      \(additionalScope)
                    ORDER BY \(orderBy)
                    LIMIT ?
                )
                SELECT i.path, i.name, i.kind, COALESCE(u.launch_count, 0),
                       u.last_launched, i.modified_at, i.file_size
                FROM candidates i
                LEFT JOIN usage u ON u.path = i.path
                WHERE i.normalized_name LIKE ? ESCAPE '\\'
                ORDER BY \(orderBy)
                LIMIT ?
                """
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if !filter.isEmpty {
            let candidateLimit = max(limit * 10, 10_000)
            sqlite3_bind_int(statement, bindIndex, Int32(candidateLimit))
            bindIndex += 1
            bind("%\(escapeLike(filter))%", at: bindIndex, to: statement)
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var results: [SearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0),
                  let nameText = sqlite3_column_text(statement, 1) else {
                continue
            }
            let lastLaunched = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
            let modifiedAt = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            let fileSize = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 6)
            results.append(SearchResult(
                path: String(cString: pathText),
                name: String(cString: nameText),
                kind: .file,
                launchCount: Int(sqlite3_column_int(statement, 3)),
                lastLaunched: lastLaunched,
                modifiedAt: modifiedAt,
                fileSize: fileSize,
                score: 0
            ))
        }
        return results
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw lastError()
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw lastError()
        }
        return statement
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func escapeLike(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func lastError() -> DatabaseError {
        DatabaseError(
            database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Database unavailable"
        )
    }
}

struct DatabaseError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
