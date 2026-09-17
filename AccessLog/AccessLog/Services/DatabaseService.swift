import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .openFailed(let m), .prepareFailed(let m), .stepFailed(let m):
            return m
        case .notFound:
            return "Record not found."
        }
    }
}

final class DatabaseService: @unchecked Sendable {
    static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.accesslog.database")

    private init() {
        open()
        createSchema()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func open() {
        let path = AppPaths.databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            fatalError("SQLite open failed: \(message)")
        }
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS access_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            purpose TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            synced_at TEXT
        );
        """
        execute(sql)
    }

    func insert(name: String, purpose: String, createdAt: Date = Date()) throws -> AccessRecord {
        try queue.sync {
            let sql = """
            INSERT INTO access_logs (name, purpose, created_at, sync_status, synced_at)
            VALUES (?, ?, ?, ?, NULL);
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastError())
            }

            let created = Self.storeFormatter.string(from: createdAt)
            bindText(statement, 1, name)
            bindText(statement, 2, purpose)
            bindText(statement, 3, created)
            bindText(statement, 4, SyncStatus.pending.rawValue)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastError())
            }

            let id = sqlite3_last_insert_rowid(db)
            return AccessRecord(
                id: id,
                name: name,
                purpose: purpose,
                createdAt: createdAt,
                syncStatus: .pending,
                syncedAt: nil
            )
        }
    }

    func pendingRecords() throws -> [AccessRecord] {
        try queue.sync {
            let sql = """
            SELECT id, name, purpose, created_at, sync_status, synced_at
            FROM access_logs
            WHERE sync_status = ?
            ORDER BY id ASC;
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastError())
            }

            bindText(statement, 1, SyncStatus.pending.rawValue)

            var records: [AccessRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                records.append(rowToRecord(statement))
            }
            return records
        }
    }

    func markSynced(id: Int64, at date: Date = Date()) throws {
        try queue.sync {
            let sql = """
            UPDATE access_logs
            SET sync_status = ?, synced_at = ?
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastError())
            }

            bindText(statement, 1, SyncStatus.synced.rawValue)
            bindText(statement, 2, Self.storeFormatter.string(from: date))
            sqlite3_bind_int64(statement, 3, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastError())
            }
        }
    }

    private func execute(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            fatalError("SQLite exec failed: \(lastError())")
        }
    }

    private func lastError() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, SQLITE_TRANSIENT)
        }
    }

    private func rowToRecord(_ statement: OpaquePointer?) -> AccessRecord {
        let id = sqlite3_column_int64(statement, 0)
        let name = columnText(statement, 1)
        let purpose = columnText(statement, 2)
        let createdRaw = columnText(statement, 3)
        let statusRaw = columnText(statement, 4)
        let syncedRaw = optionalColumnText(statement, 5)

        let createdAt = Self.storeFormatter.date(from: createdRaw) ?? Date()
        let syncedAt = syncedRaw.flatMap { Self.storeFormatter.date(from: $0) }
        let status = SyncStatus(rawValue: statusRaw) ?? .pending

        return AccessRecord(
            id: id,
            name: name,
            purpose: purpose,
            createdAt: createdAt,
            syncStatus: status,
            syncedAt: syncedAt
        )
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func optionalColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private static let storeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TrustedTimeService.ist
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
