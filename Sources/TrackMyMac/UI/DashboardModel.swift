import SwiftUI
import Combine

enum Period: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "近 7 天"
    case month = "近 30 天"
    case year = "近 365 天"
    var id: String { rawValue }

    func range(now: Date = Date()) -> (Date, Date) {
        let cal = Calendar.current
        switch self {
        case .today:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
            return (start, now)
        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))!
            return (start, now)
        case .year:
            let start = cal.date(byAdding: .day, value: -364, to: cal.startOfDay(for: now))!
            return (start, now)
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
                case .today: return 60 * 30   // 30-min buckets
                case .week: return 3600 * 6   // 6-hour buckets
                case .month: return 86400     // daily
                case .year: return 86400 * 7  // weekly
                }
            }()
            let buckets = Database.shared.minuteBuckets(from: from, to: to, bucketSec: bucketSec)
            let timeline = buckets.map { (Date(timeIntervalSince1970: TimeInterval($0.bucket * Int64(bucketSec))), $0.keys, $0.clicks, $0.activeSec) }
            let apps = Database.shared.topApps(from: from, to: to, limit: 10)
            let cats = Database.shared.keyCategoryBreakdown(from: from, to: to)

            DispatchQueue.main.async {
                var s = Summary()
                s.keys = sum.keys
                s.clicks = sum.clicks
                s.scrolls = sum.scrolls
                s.activeSec = sum.activeSec
                s.screenSec = sum.screenSec
                s.moveDist = sum.moveDist
                s.topApps = apps
                s.keyCategories = cats
                s.timeline = timeline.map { (epochStart: $0.0, keys: $0.1, clicks: $0.2, activeSec: $0.3) }
                self.summary = s
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
