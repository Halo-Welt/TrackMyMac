import Foundation
import os

enum Log {
    static let log = OSLog(subsystem: "com.trackmymac.app", category: "main")
    static var suppressConsoleLogs = false
    static var mirrorConsoleLogsToStandardError = false

    static func info(_ msg: String) {
        os_log("%{public}@", log: log, type: .info, msg)
        #if DEBUG
        writeConsole("[INFO] \(msg)")
        #endif
    }

    static func error(_ msg: String) {
        os_log("%{public}@", log: log, type: .error, msg)
        writeConsole("[ERROR] \(msg)")
    }

    static func debug(_ msg: String) {
        #if DEBUG
        writeConsole("[DEBUG] \(msg)")
        #endif
    }

    private static func writeConsole(_ msg: String) {
        guard !suppressConsoleLogs else { return }
        if mirrorConsoleLogsToStandardError {
            FileHandle.standardError.write(Data((msg + "\n").utf8))
        } else {
            print(msg)
        }
    }
}

enum Paths {
    static var supportDir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("TrackMyMac", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // Mark as excluded from backups (Time Machine + iCloud)
            var url = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return dir
    }

    static var databaseURL: URL {
        supportDir.appendingPathComponent("tracker.db")
    }
}
