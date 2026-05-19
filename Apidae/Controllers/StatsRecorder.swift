import Foundation
import SQLite3
import os.log

private let logger = Logger(subsystem: "app.getapidae.mac", category: "StatsRecorder")

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum EventType: String, Sendable {
    case lock
    case unlock
}

enum TriggerMethod: String, Sendable {
    case hotkey
    case menu
    case urlScheme       = "url_scheme"
    case settingsButton  = "settings_button"
    case touchID         = "touchid"
    case password
    case force
    case unknown
}

struct StatsEvent: Sendable, Equatable {
    let id: Int64
    let timestamp: Date
    let eventType: EventType
    let triggerMethod: TriggerMethod
    let durationSeconds: TimeInterval?
}

/// Wraps the raw SQLite handle so its lifetime is tied to a regular class deinit
/// rather than the actor's deinit (which can't touch isolated state).
private final class SQLiteHandle {
    let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close_v2(handle) }
            throw StatsRecorder.StatsError.openFailed(rc, msg)
        }
        self.db = handle
    }

    deinit {
        sqlite3_close_v2(db)
    }
}

actor StatsRecorder {
    enum Location {
        case `default`
        case file(URL)
        case memory
    }

    enum StatsError: Error {
        case openFailed(Int32, String)
        case prepareFailed(Int32, String)
        case stepFailed(Int32, String)
        case execFailed(Int32, String)
    }

    private let handle: SQLiteHandle
    private var db: OpaquePointer { handle.db }

    init(location: Location = .default) throws {
        let path: String
        switch location {
        case .default:    path = try Self.defaultDatabasePath().path
        case .file(let url): path = url.path
        case .memory:     path = ":memory:"
        }
        self.handle = try SQLiteHandle(path: path)

        try Self.exec(handle.db, "PRAGMA journal_mode = WAL;")
        try Self.exec(handle.db, """
            CREATE TABLE IF NOT EXISTS events (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp        REAL    NOT NULL,
                event_type       TEXT    NOT NULL CHECK(event_type IN ('lock','unlock')),
                trigger_method   TEXT    NOT NULL,
                duration_seconds REAL
            );
            """)
        try Self.exec(handle.db, "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);")

        logger.info("Stats DB ready at \(path, privacy: .public)")
    }

    // MARK: - Recording

    func recordLock(trigger: TriggerMethod, at timestamp: Date) throws {
        try insertEvent(type: .lock, trigger: trigger, timestamp: timestamp, duration: nil)
    }

    func recordUnlock(trigger: TriggerMethod, durationSeconds: TimeInterval, at timestamp: Date) throws {
        try insertEvent(type: .unlock, trigger: trigger, timestamp: timestamp, duration: durationSeconds)
    }

    // MARK: - Queries (used by tests now, by StatsService in commit 2)

    func allEvents() throws -> [StatsEvent] {
        let sql = "SELECT id, timestamp, event_type, trigger_method, duration_seconds FROM events ORDER BY timestamp ASC, id ASC;"
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw StatsError.prepareFailed(rc, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var results: [StatsEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let ts = sqlite3_column_double(stmt, 1)
            let typeRaw = String(cString: sqlite3_column_text(stmt, 2))
            let trigRaw = String(cString: sqlite3_column_text(stmt, 3))
            let dur: TimeInterval? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(stmt, 4)
            results.append(StatsEvent(
                id: id,
                timestamp: Date(timeIntervalSince1970: ts),
                eventType: EventType(rawValue: typeRaw) ?? .lock,
                triggerMethod: TriggerMethod(rawValue: trigRaw) ?? .unknown,
                durationSeconds: dur
            ))
        }
        return results
    }

    func deleteAll() throws {
        try Self.exec(db, "DELETE FROM events;")
    }

    // MARK: - Private

    private func insertEvent(type: EventType, trigger: TriggerMethod, timestamp: Date, duration: TimeInterval?) throws {
        let sql = "INSERT INTO events (timestamp, event_type, trigger_method, duration_seconds) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw StatsError.prepareFailed(rc, String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, trigger.rawValue, -1, SQLITE_TRANSIENT)
        if let duration {
            sqlite3_bind_double(stmt, 4, duration)
        } else {
            sqlite3_bind_null(stmt, 4)
        }

        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE else {
            throw StatsError.stepFailed(stepRC, String(cString: sqlite3_errmsg(db)))
        }

        NotificationCenter.default.post(name: .apidaeStatsDidChange, object: nil)
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw StatsError.execFailed(rc, msg)
        }
    }

    private static func defaultDatabasePath() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Apidae", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stats.db")
    }
}
