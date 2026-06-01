import SwiftUI
import Combine

enum Period: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "近 7 天"
    case month = "近 30 天"
    case year = "近 365 天"
    var id: String { rawValue }

    /// Calendar bounds aligned to day boundaries so the chart x-axis can show
    /// the full period (e.g. today = 00:00 → 24:00 even at 9 AM).
    func range(now: Date = Date()) -> (Date, Date) {
        let cal = Calendar.current
        switch self {
        case .today:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .week:
            let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            let start = cal.date(byAdding: .day, value: -7, to: endDay)!
            return (start, endDay)
        case .month:
            let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            let start = cal.date(byAdding: .day, value: -30, to: endDay)!
            return (start, endDay)
        case .year:
            let endDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            let start = cal.date(byAdding: .day, value: -365, to: endDay)!
            return (start, endDay)
        }
    }
}

struct Summary {
    var keys: Int = 0
    var clicks: Int = 0
    var scrolls: Int = 0
    var activeSec: Int = 0
    var screenSec: Int = 0
    var moveDist: Double = 0
    var topApps: [(name: String, seconds: Double)] = []
    var keyCategories: [(String, Int)] = []
    /// Buckets for timeline. Each tuple: (epochStart, keys, clicks, activeSec)
    var timeline: [(epochStart: Date, keys: Int, clicks: Int, activeSec: Int)] = []
    /// Per-keycode counts for heatmap.
    var keyHeatmap: [Int: Int] = [:]
    /// Top shortcuts (e.g. "⌘⇧A") with their counts.
    var topShortcuts: [(label: String, count: Int)] = []
    /// Inclusive period bounds — used to set chart x-axis domain.
    var periodStart: Date = Date()
    var periodEnd: Date = Date()
    /// Bucket size in seconds.
    var bucketSec: Int = 60
}

final class DashboardModel: ObservableObject {
    @Published var period: Period = .today
    @Published var summary = Summary()
    @Published var refreshing = false
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let p = period
        let (s, e) = p.range()
        DispatchQueue.global(qos: .userInitiated).async {
            let from = s.timeIntervalSince1970
            let to = e.timeIntervalSince1970
            let sum = Database.shared.summary(from: from, to: to)
            let bucketSec: Int = {
                switch p {
                case .today: return 60 * 30   // 30-min buckets across 0..24
                case .week: return 3600 * 6   // 6-hour buckets across 7 days
                case .month: return 86400     // daily across 30 days
                case .year: return 86400 * 7  // weekly across 52 weeks
                }
            }()
            // Build complete bucket list (including zero buckets) so the timeline
            // chart spans the full period regardless of whether data exists.
            let dbBuckets = Database.shared.minuteBuckets(from: from, to: to, bucketSec: bucketSec)
            var byBucket = Dictionary(uniqueKeysWithValues: dbBuckets.map { ($0.bucket, ($0.keys, $0.clicks, $0.activeSec)) })
            let firstBucket = Int64(from) / Int64(bucketSec)
            let lastBucket = Int64(to - 1) / Int64(bucketSec)
            var timeline: [(Date, Int, Int, Int)] = []
            if lastBucket >= firstBucket {
                for b in firstBucket...lastBucket {
                    let v = byBucket.removeValue(forKey: b) ?? (0, 0, 0)
                    let date = Date(timeIntervalSince1970: TimeInterval(b * Int64(bucketSec)))
                    timeline.append((date, v.0, v.1, v.2))
                }
            }

            let apps = Database.shared.topApps(from: from, to: to, limit: 10)
            let cats = Database.shared.keyCategoryBreakdown(from: from, to: to)
            let heatmap = Database.shared.keycodeHeatmap(from: from, to: to)
            let shortcuts = Database.shared.topShortcuts(from: from, to: to, limit: 10)

            DispatchQueue.main.async {
                var result = Summary()
                result.keys = sum.keys
                result.clicks = sum.clicks
                result.scrolls = sum.scrolls
                result.activeSec = sum.activeSec
                result.screenSec = sum.screenSec
                result.moveDist = sum.moveDist
                result.topApps = apps
                result.keyCategories = cats
                result.keyHeatmap = heatmap
                result.topShortcuts = shortcuts
                result.timeline = timeline.map { (epochStart: $0.0, keys: $0.1, clicks: $0.2, activeSec: $0.3) }
                result.periodStart = s
                result.periodEnd = e
                result.bucketSec = bucketSec
                self.summary = result
            }
        }
    }
}

func formatDuration(_ seconds: Int) -> String {
    if seconds <= 0 { return "0 分钟" }
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    if h > 0 { return "\(h) 小时 \(m) 分钟" }
    return "\(m) 分钟"
}
