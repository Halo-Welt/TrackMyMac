import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject var model = DashboardModel()
    @ObservedObject var perms: PermissionsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    if !perms.allGranted {
                        permissionBanner
                    }
                    statsCards
                    timelineCard
                    keyboardHeatmapCard
                    shortcutsCard
                    topAppsCard
                    footer
                }
                .padding(20)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .foregroundStyle(.tint)
                .font(.title2)
            Text("TrackMyMac")
                .font(.title2.bold())
            Spacer()
            Picker("周期", selection: $model.period) {
                ForEach(Period.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)
            .onChange(of: model.period) { model.refresh() }
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("立即刷新")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("尚未获得全部所需权限").font(.headline)
                Text("缺少权限时部分数据无法采集。请在系统设置中授予以下权限后重启 App。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !perms.accessibility {
                        Button("打开 辅助功能") { Permissions.openAccessibilitySettings() }
                    }
                    Button("打开 输入监控") { Permissions.openInputMonitoringSettings() }
                    if !perms.screenRecording {
                        Button("打开 屏幕录制") { Permissions.openScreenRecordingSettings() }
                    }
                    Button("重新检测") { perms.refresh() }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
    }

    private var statsCards: some View {
        let s = model.summary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            StatCard(title: "键盘按键", value: "\(s.keys)", subtitle: "次", systemImage: "keyboard", tint: .blue)
            StatCard(title: "鼠标点击", value: "\(s.clicks)", subtitle: "次", systemImage: "cursorarrow.click.2", tint: .pink)
            StatCard(title: "活跃时长", value: formatDuration(s.activeSec), subtitle: nil, systemImage: "bolt.fill", tint: .green)
            StatCard(title: "亮屏时长", value: formatDuration(s.screenSec), subtitle: "鼠标移动 \(Int(s.moveDist)) px", systemImage: "display", tint: .orange)
        }
    }

    private var timelineCard: some View {
        let timeline = model.summary.timeline
        let s = model.summary.periodStart
        let e = model.summary.periodEnd
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("活动时间线").font(.headline)
                Spacer()
                Text(periodSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if timeline.isEmpty {
                placeholder("暂无活动数据")
                    .frame(height: 220)
            } else {
                Chart {
                    ForEach(Array(timeline.enumerated()), id: \.offset) { _, b in
                        BarMark(
                            x: .value("时间", b.epochStart),
                            y: .value("按键", b.keys),
                            width: .fixed(barWidth)
                        )
                        .foregroundStyle(by: .value("类型", "按键"))
                        BarMark(
                            x: .value("时间", b.epochStart),
                            y: .value("点击", b.clicks),
                            width: .fixed(barWidth)
                        )
                        .foregroundStyle(by: .value("类型", "点击"))
                    }
                }
                .chartForegroundStyleScale([
                    "按键": Color.blue.gradient,
                    "点击": Color.pink.gradient
                ])
                .chartXScale(domain: s...e)
                .chartXAxis { timelineAxisMarks }
                .chartLegend(.visible)
                .frame(height: 240)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    /// X-axis tick configuration tuned per period.
    @AxisContentBuilder
    private var timelineAxisMarks: some AxisContent {
        switch model.period {
        case .today:
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .week:
            AxisMarks(values: .stride(by: .day, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 3)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        case .year:
            AxisMarks(values: .stride(by: .month, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }

    private var barWidth: CGFloat {
        switch model.period {
        case .today: return 8
        case .week: return 14
        case .month: return 6
        case .year: return 5
        }
    }

    private var topAppsCard: some View {
        let apps = model.summary.topApps
        return VStack(alignment: .leading, spacing: 10) {
            Text("应用使用 Top 10").font(.headline)
            if apps.isEmpty {
                placeholder("暂无应用数据").frame(height: 200)
            } else {
                let total = max(apps.reduce(0) { $0 + $1.seconds }, 1)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(apps.enumerated()), id: \.offset) { _, a in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(a.name).lineLimit(1)
                                Spacer()
                                Text(formatDuration(Int(a.seconds))).foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(2, geo.size.width * a.seconds / total))
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var keyboardHeatmapCard: some View {
        let map = model.summary.keyHeatmap
        let maxCount = max(map.values.max() ?? 0, 1)
        let totalKeys = map.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("键盘热力图").font(.headline)
                Spacer()
                Text("总按键 \(totalKeys) · 命中键 \(map.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if totalKeys == 0 {
                placeholder("暂无按键数据").frame(height: 280)
            } else {
                KeyboardHeatmap(counts: map, maxCount: maxCount)
                    .frame(height: 280)
            }
            HStack(spacing: 6) {
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(KeyboardHeatmap.color(for: Double(i) / 5.0))
                        .frame(width: 18, height: 10)
                }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var shortcutsCard: some View {
        let shortcuts = model.summary.topShortcuts
        return VStack(alignment: .leading, spacing: 10) {
            Text("组合键 Top 10").font(.headline)
            if shortcuts.isEmpty {
                placeholder("暂无组合键数据").frame(height: 120)
            } else {
                let total = max(shortcuts.reduce(0) { $0 + $1.count }, 1)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 8) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, sc in
                        HStack(spacing: 10) {
                            Text(sc.label)
                                .font(.system(.title3, design: .monospaced).bold())
                                .frame(minWidth: 92, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.15))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(2, geo.size.width * Double(sc.count) / Double(total)))
                                }
                            }
                            .frame(height: 8)
                            Text("\(sc.count)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var footer: some View {
        HStack {
            Image(systemName: "lock.shield")
            Text("数据仅存储于本机：\(Paths.databaseURL.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([Paths.databaseURL])
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private var periodSubtitle: String {
        let (s, e) = model.period.range()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(f.string(from: s)) → \(f.string(from: e))"
    }

    private func placeholder(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.windowBackgroundColor))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value).font(.title.bold())
            if let s = subtitle {
                Text(s).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(" ").font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.windowBackgroundColor)).shadow(color: .black.opacity(0.08), radius: 4, y: 2))
    }
}
