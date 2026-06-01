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
                    HStack(alignment: .top, spacing: 16) {
                        topAppsCard
                        keyCategoryCard
                    }
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
            StatCard(title: "鼠标点击", value: "\(s.clicks)", subtitle: "次  滚轮 \(s.scrolls)", systemImage: "cursorarrow.click.2", tint: .pink)
            StatCard(title: "活跃时长", value: formatDuration(s.activeSec), subtitle: nil, systemImage: "bolt.fill", tint: .green)
            StatCard(title: "亮屏时长", value: formatDuration(s.screenSec), subtitle: "鼠标移动 \(Int(s.moveDist)) px", systemImage: "display", tint: .orange)
        }
    }

    private var timelineCard: some View {
        let timeline = model.summary.timeline
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("活动时间线").font(.headline)
                Spacer()
                Text(periodSubtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            if timeline.isEmpty {
                placeholder("暂无活动数据")
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(Array(timeline.enumerated()), id: \.offset) { _, b in
                        BarMark(
                            x: .value("时间", b.epochStart, unit: chartUnit),
                            y: .value("按键", b.keys)
                        )
                        .foregroundStyle(.blue.gradient)
                        BarMark(
                            x: .value("时间", b.epochStart, unit: chartUnit),
                            y: .value("点击", b.clicks)
                        )
                        .foregroundStyle(.pink.gradient)
                    }
                }
                .chartLegend(.visible)
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(cardBackground)
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

    private var keyCategoryCard: some View {
        let cats = model.summary.keyCategories
        return VStack(alignment: .leading, spacing: 10) {
            Text("按键类别分布").font(.headline)
            if cats.isEmpty {
                placeholder("暂无键盘数据").frame(height: 200)
            } else {
                Chart {
                    ForEach(Array(cats.enumerated()), id: \.offset) { _, c in
                        SectorMark(
                            angle: .value("数量", c.1),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.2
                        )
                        .foregroundStyle(by: .value("类别", localized(c.0)))
                        .annotation(position: .overlay) {
                            if Double(c.1) / Double(max(cats.reduce(0) { $0 + $1.1 }, 1)) > 0.05 {
                                Text("\(c.1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var chartUnit: Calendar.Component {
        switch model.period {
        case .today: return .minute
        case .week: return .hour
        case .month: return .day
        case .year: return .day
        }
    }

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

    private func localized(_ raw: String) -> String {
        switch raw {
        case "letter": return "字母"
        case "digit": return "数字"
        case "symbol": return "符号"
        case "whitespace": return "空白键"
        case "navigation": return "导航键"
        case "function": return "功能键"
        case "modifier": return "修饰键"
        case "shortcut": return "快捷键"
        default: return "其他"
        }
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
