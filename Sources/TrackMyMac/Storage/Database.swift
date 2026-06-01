import Foundation
import SQLite3

/// Lightweight wrapper around SQLite. Single writer, multiple reader.
final class Database {
    static let shared = Database()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.trackmymac.db")

    private init() {
        open()
        migrate()
    }

    private func open() {
        let path = Paths.databaseURL.path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            Log.error("Open db failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA foreign_keys=ON;")
        Log.info("DB opened at: \(path)")
    }

    private func migrate() {
        let stmts = [
            """
            CREATE TABLE IF NOT EXISTS keystrokes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                category TEXT NOT NULL,
                cipher BLOB
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_ks_ts ON keystrokes(ts);",
            // v1.0.2: keycode + modifier mask + display label (for shortcut analytics)
            "ALTER TABLE keystrokes ADD COLUMN keycode INTEGER;",
            "ALTER TABLE keystrokes ADD COLUMN mods INTEGER DEFAULT 0;",
            "ALTER TABLE keystrokes ADD COLUMN shortcut_label TEXT;",
            "CREATE INDEX IF NOT EXISTS idx_ks_keycode ON keystrokes(keycode);",
            "CREATE INDEX IF NOT EXISTS idx_ks_shortcut ON keystrokes(shortcut_label);",
            """
            CREATE TABLE IF NOT EXISTS mouse_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ts REAL NOT NULL,
                kind TEXT NOT NULL,
                x REAL,
                y REAL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_me_ts ON mouse_events(ts);",
            """
            CREATE TABLE IF NOT EXISTS app_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_ts REAL NOT NULL,
                end_ts REAL,
                bundle_id TEXT,
                app_name TEXT,
                window_title TEXT
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_as_start ON app_sessions(start_ts);",
            """
            CREATE TABLE IF NOT EXISTS active_minutes (
                minute_ts INTEGER PRIMARY KEY,
                key_count INTEGER DEFAULT 0,
                click_count INTEGER DEFAULT 0,
                scroll_count INTEGER DEFAULT 0,
                move_distance REAL DEFAULT 0,
                active_seconds INTEGER DEFAULT 0,
                screen_on_seconds INTEGER DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS meta (
                k TEXT PRIMARY KEY,
                v TEXT
            );
            """
        ]
        for s in stmts { exec(s) }
    }

    @discardableResult
    func exec(_ sql: String) -> Bool {
        var ok = false
        queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK {
                ok = true
            } else {
                if let e = err {
                    Log.error("SQL error: \(String(cString: e)) for: \(sql)")
                    sqlite3_free(err)
                }
            }
        }
        return ok
    }

    // MARK: - Inserts

    func insertKeystroke(ts: Double, category: String, cipher: Data?,
                         keycode: Int? = nil, mods: Int = 0, shortcutLabel: String? = nil) {
        queue.async {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO keystrokes (ts, category, cipher, keycode, mods, shortcut_label) VALUES (?, ?, ?, ?, ?, ?);"
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, ts)
                sqlite3_bind_text(stmt, 2, (category as NSString).utf8String, -1, nil)
                if let c = cipher {
                    _ = c.withUnsafeBytes { p -> Int32 in
                        sqlite3_bind_blob(stmt, 3, p.baseAddress, Int32(c.count), nil)
                    }
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                if let kc = keycode {
                    sqlite3_bind_int(stmt, 4, Int32(kc))
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_int(stmt, 5, Int32(mods))
                bindOptText(stmt, 6, shortcutLabel)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func insertMouseEvent(ts: Double, kind: String, x: Double, y: Double) {
        queue.async {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO mouse_events (ts, kind, x, y) VALUES (?, ?, ?, ?);"
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, ts)
                sqlite3_bind_text(stmt, 2, (kind as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 3, x)
                sqlite3_bind_double(stmt, 4, y)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func startAppSession(ts: Double, bundleId: String?, appName: String?, windowTitle: String?) -> Int64 {
        var rowId: Int64 = 0
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO app_sessions (start_ts, bundle_id, app_name, window_title) VALUES (?, ?, ?, ?);"
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, ts)
                bindOptText(stmt, 2, bundleId)
                bindOptText(stmt, 3, appName)
                bindOptText(stmt, 4, windowTitle)
                sqlite3_step(stmt)
                rowId = sqlite3_last_insert_rowid(self.db)
            }
            sqlite3_finalize(stmt)
        }
        return rowId
    }

    func endAppSession(id: Int64, ts: Double) {
        queue.async {
            var stmt: OpaquePointer?
            let sql = "UPDATE app_sessions SET end_ts=? WHERE id=?;"
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, ts)
                sqlite3_bind_int64(stmt, 2, id)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func bumpMinute(minuteTs: Int64,
                    keys: Int = 0,
                    clicks: Int = 0,
                    scrolls: Int = 0,
                    moveDistance: Double = 0,
                    activeDelta: Int = 0,
                    screenOnDelta: Int = 0) {
        queue.async {
            let sql = """
            INSERT INTO active_minutes (minute_ts, key_count, click_count, scroll_count, move_distance, active_seconds, screen_on_seconds)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(minute_ts) DO UPDATE SET
              key_count = key_count + excluded.key_count,
              click_count = click_count + excluded.click_count,
              scroll_count = scroll_count + excluded.scroll_count,
              move_distance = move_distance + excluded.move_distance,
              active_seconds = MIN(60, active_seconds + excluded.active_seconds),
              screen_on_seconds = MIN(60, screen_on_seconds + excluded.screen_on_seconds);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, minuteTs)
                sqlite3_bind_int(stmt, 2, Int32(keys))
                sqlite3_bind_int(stmt, 3, Int32(clicks))
                sqlite3_bind_int(stmt, 4, Int32(scrolls))
                sqlite3_bind_double(stmt, 5, moveDistance)
                sqlite3_bind_int(stmt, 6, Int32(activeDelta))
                sqlite3_bind_int(stmt, 7, Int32(screenOnDelta))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Queries

    func summary(from: Double, to: Double) -> (keys: Int, clicks: Int, scrolls: Int, activeSec: Int, screenSec: Int, moveDist: Double) {
        var result: (Int, Int, Int, Int, Int, Double) = (0, 0, 0, 0, 0, 0)
        queue.sync {
            let sql = """
            SELECT IFNULL(SUM(key_count),0), IFNULL(SUM(click_count),0), IFNULL(SUM(scroll_count),0),
                   IFNULL(SUM(active_seconds),0), IFNULL(SUM(screen_on_seconds),0), IFNULL(SUM(move_distance),0)
              FROM active_minutes
             WHERE minute_ts >= ? AND minute_ts < ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, Int64(from / 60))
                sqlite3_bind_int64(stmt, 2, Int64(to / 60))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    result = (
                        Int(sqlite3_column_int(stmt, 0)),
                        Int(sqlite3_column_int(stmt, 1)),
                        Int(sqlite3_column_int(stmt, 2)),
                        Int(sqlite3_column_int(stmt, 3)),
                        Int(sqlite3_column_int(stmt, 4)),
                        sqlite3_column_double(stmt, 5)
                    )
                }
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    func minuteBuckets(from: Double, to: Double, bucketSec: Int) -> [(bucket: Int64, keys: Int, clicks: Int, activeSec: Int)] {
        var rows: [(Int64, Int, Int, Int)] = []
        queue.sync {
            let sql = """
            SELECT (minute_ts*60 / ?) AS bucket,
                   SUM(key_count), SUM(click_count), SUM(active_seconds)
              FROM active_minutes
             WHERE minute_ts >= ? AND minute_ts < ?
             GROUP BY bucket
             ORDER BY bucket ASC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(bucketSec))
                sqlite3_bind_int64(stmt, 2, Int64(from / 60))
                sqlite3_bind_int64(stmt, 3, Int64(to / 60))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append((
                        sqlite3_column_int64(stmt, 0),
                        Int(sqlite3_column_int(stmt, 1)),
                        Int(sqlite3_column_int(stmt, 2)),
                        Int(sqlite3_column_int(stmt, 3))
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return rows
    }

    func topApps(from: Double, to: Double, limit: Int = 10) -> [(name: String, seconds: Double)] {
        var rows: [(String, Double)] = []
        queue.sync {
            let sql = """
            SELECT IFNULL(app_name,'(Unknown)') AS name,
                   SUM(MIN(IFNULL(end_ts, ?), ?) - MAX(start_ts, ?)) AS sec
              FROM app_sessions
             WHERE IFNULL(end_ts, ?) > ? AND start_ts < ?
             GROUP BY name
             ORDER BY sec DESC
             LIMIT ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                let now = Date().timeIntervalSince1970
                sqlite3_bind_double(stmt, 1, now)
                sqlite3_bind_double(stmt, 2, to)
                sqlite3_bind_double(stmt, 3, from)
                sqlite3_bind_double(stmt, 4, now)
                sqlite3_bind_double(stmt, 5, from)
                sqlite3_bind_double(stmt, 6, to)
                sqlite3_bind_int(stmt, 7, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let name = String(cString: sqlite3_column_text(stmt, 0))
                    let sec = sqlite3_column_double(stmt, 1)
                    if sec > 0 { rows.append((name, sec)) }
                }
            }
            sqlite3_finalize(stmt)
        }
        return rows
    }

    func keyCategoryBreakdown(from: Double, to: Double) -> [(String, Int)] {
        var rows: [(String, Int)] = []
        queue.sync {
            let sql = """
            SELECT category, COUNT(*) FROM keystrokes
             WHERE ts >= ? AND ts < ?
             GROUP BY category ORDER BY 2 DESC;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, from)
                sqlite3_bind_double(stmt, 2, to)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append((String(cString: sqlite3_column_text(stmt, 0)),
                                 Int(sqlite3_column_int(stmt, 1))))
                }
            }
            sqlite3_finalize(stmt)
        }
        return rows
    }

    func keycodeHeatmap(from: Double, to: Double) -> [Int: Int] {
        var dict: [Int: Int] = [:]
        queue.sync {
            let sql = """
            SELECT keycode, COUNT(*) FROM keystrokes
             WHERE ts >= ? AND ts < ? AND keycode IS NOT NULL
             GROUP BY keycode;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, from)
                sqlite3_bind_double(stmt, 2, to)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let kc = Int(sqlite3_column_int(stmt, 0))
                    let n = Int(sqlite3_column_int(stmt, 1))
                    dict[kc] = n
                }
            }
            sqlite3_finalize(stmt)
        }
        return dict
    }

    func topShortcuts(from: Double, to: Double, limit: Int = 10) -> [(label: String, count: Int)] {
        var rows: [(String, Int)] = []
        queue.sync {
            let sql = """
            SELECT shortcut_label, COUNT(*) FROM keystrokes
             WHERE ts >= ? AND ts < ? AND shortcut_label IS NOT NULL
             GROUP BY shortcut_label
             ORDER BY 2 DESC
             LIMIT ?;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, from)
                sqlite3_bind_double(stmt, 2, to)
                sqlite3_bind_int(stmt, 3, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append((String(cString: sqlite3_column_text(stmt, 0)),
                                 Int(sqlite3_column_int(stmt, 1))))
                }
            }
            sqlite3_finalize(stmt)
        }
        return rows
    }
}

private func bindOptText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
    if let v = value {
        // SQLITE_TRANSIENT
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(stmt, idx)
    }
}
