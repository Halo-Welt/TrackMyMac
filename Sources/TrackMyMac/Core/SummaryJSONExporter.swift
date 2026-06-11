import Darwin
import Foundation

enum SummaryJSONExporter {
    private enum PeriodArg: String {
        case today
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case year = "365d"

        var label: String { rawValue }

        func range(now: Date = Date()) -> (Date, Date) {
            let cal = Calendar.current
            let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            switch self {
            case .today:
                return (cal.startOfDay(for: now), endDay)
            case .sevenDays:
                return (cal.date(byAdding: .day, value: -7, to: endDay)!, endDay)
            case .thirtyDays:
                return (cal.date(byAdding: .day, value: -30, to: endDay)!, endDay)
            case .year:
                return (cal.date(byAdding: .day, value: -365, to: endDay)!, endDay)
            }
        }
    }

    private struct Export: Encodable {
        let period: String
        let from: String
        let to: String
        let generatedAt: String
        let keyCount: Int
        let clickCount: Int
        let scrollCount: Int
        let moveDistance: Double
        let activeSeconds: Int
        let screenOnSeconds: Int
        let topApps: [AppUsage]
        let keyCategories: [CountItem]
    }

    private struct AppUsage: Encodable {
        let name: String
        let seconds: Int
    }

    private struct CountItem: Encodable {
        let name: String
        let count: Int
    }

    static func runIfNeeded(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let flagIndex = arguments.firstIndex(of: "--summary-json") else {
            return false
        }
        Log.mirrorConsoleLogsToStandardError = true

        guard arguments.indices.contains(flagIndex + 1),
              let period = PeriodArg(rawValue: arguments[flagIndex + 1]) else {
            printUsage()
            exit(2)
        }

        Log.suppressConsoleLogs = true

        do {
            let payload = try makePayload(period: period)
            FileHandle.standardOutput.write(payload)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            writeError("Failed to export summary JSON: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func makePayload(period: PeriodArg) throws -> Data {
        let (start, end) = period.range()
        let from = start.timeIntervalSince1970
        let to = end.timeIntervalSince1970
        let summary = Database.shared.summary(from: from, to: to)

        let export = Export(
            period: period.label,
            from: isoString(start),
            to: isoString(end),
            generatedAt: isoString(Date()),
            keyCount: summary.keys,
            clickCount: summary.clicks,
            scrollCount: summary.scrolls,
            moveDistance: summary.moveDist,
            activeSeconds: summary.activeSec,
            screenOnSeconds: summary.screenSec,
            topApps: Database.shared.topApps(from: from, to: to, limit: 10).map {
                AppUsage(name: $0.name, seconds: Int($0.seconds.rounded()))
            },
            keyCategories: Database.shared.keyCategoryBreakdown(from: from, to: to).map {
                CountItem(name: $0.0, count: $0.1)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func printUsage() {
        writeError("""
        Usage:
          TrackMyMac --summary-json <today|7d|30d|365d>

        Exports aggregate usage statistics only. Raw keystroke ciphertext is never exported.
        """)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
