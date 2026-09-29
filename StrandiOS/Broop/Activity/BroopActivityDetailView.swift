#if os(iOS)
import Charts
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

/// The row actions a detail screen can offer, supplied by the list that owns the reload and the sheets.
/// Which ones apply follows the classic row menu: detected bouts relabel / edit / dismiss, manual rows
/// edit / delete, imported history duplicates as manual and is otherwise read-only.
struct BroopActivityRowActions {
    var edit: (WorkoutRow) -> Void
    var duplicate: (WorkoutRow) -> Void
    var relabel: (WorkoutRow, String) -> Void
    var dismissDetected: (WorkoutRow) -> Void
    var delete: (WorkoutRow) -> Void

    static let relabelSports = ["Running", "Walking", "Cycling", "Strength Training", "Swimming", "Rowing",
                                "Yoga", "HIIT", "CrossFit", "Hiking", "Tennis"]

    @ViewBuilder
    func menu(for row: WorkoutRow, afterDestructive: @escaping () -> Void = {}) -> some View {
        switch WorkoutSource.classify(row.source) {
        case .detected:
            Menu("Re-label as") {
                ForEach(Self.relabelSports, id: \.self) { sport in
                    Button(sport) { relabel(row, sport) }
                }
            }
            Button("Edit details…") { edit(row) }
            Divider()
            Button("Dismiss (not a workout)", role: .destructive) { dismissDetected(row); afterDestructive() }
        case .manual:
            Button("Edit…") { edit(row) }
            Divider()
            Button("Delete", role: .destructive) { delete(row); afterDestructive() }
        case .whoop, .apple, .lifting, .activityFile:
            Button("Duplicate as manual…") { duplicate(row) }
        }
    }
}

/// WHOOP's activity detail over the classic `WorkoutDetailView` data: the session Effort, the heart-rate
/// curve across the session, the zone split (imported WHOOP percentages when the row has them, else the
/// strap's own heart rate binned into the wearer's zones), key statistics, heart-rate recovery, and the
/// recorded GPS route with its GPX / FIT export.
struct BroopActivityDetailView: View {
    let row: WorkoutRow
    let actions: BroopActivityRowActions

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    @State private var hr: [HRBucket] = []
    @State private var zoneMinutes: [Double]?
    @State private var zonesFromImport = false
    @State private var recovery: HeartRateRecovery.Result?
    @State private var route: [RouteMath.LatLng] = []
    @State private var steps: (count: Int, fromStrap: Bool)?
    @State private var loaded = false
    @State private var exportingRoute = false

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }
    private var durationS: Double { row.durationS ?? Double(max(0, row.endTs - row.startTs)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, BroopMetrics.page).padding(.top, 6)
                chips.padding(.horizontal, BroopMetrics.page).padding(.top, 12)
                headline.padding(.horizontal, BroopMetrics.page).padding(.top, 20)
                chart.padding(.top, 26)
                zones.padding(.horizontal, BroopMetrics.page).padding(.top, 18)
                keyStatistics.padding(.top, 30)
                recoverySection
                routeSection
                Text("This session's contribution to the day's Effort, as captured during the workout.")
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .padding(.horizontal, BroopMetrics.page)
                    .padding(.top, 26)
            }
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopNavHeader(center: { EmptyView() }, trailing: { actionsMenu })
        }
        .broopActivityPage()
        .task(id: "\(row.startTs)-\(row.endTs)-\(repo.refreshSeq)") { await load() }
    }

    // MARK: Header

    private var actionsMenu: some View {
        Menu {
            actions.menu(for: row, afterDestructive: { dismiss() })
            if route.count >= 2 {
                Button { exportingRoute = true } label: { Label("Export route", systemImage: "square.and.arrow.up") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Actions"))
    }

    private var header: some View {
        HStack(spacing: 12) {
            WorkoutTypeIcon(workoutType: row.sport, size: 34, weight: .semibold, color: .white)
            VStack(alignment: .leading, spacing: 2) {
                BroopCaps(WorkoutSource.displaySport(row), size: 14).lineLimit(1)
                Text(verbatim: BroopActivityFormat.span(row.startTs, row.endTs))
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer()
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .confirmationDialog("Export route", isPresented: $exportingRoute, titleVisibility: .visible) {
            Button("GPX — Strava, Garmin, most apps") { exportRoute(.gpx) }
            Button("FIT — Garmin Connect") { exportRoute(.fit) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this route as a standard file you can import into Strava, Garmin Connect, and other apps.")
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            BroopActivityChip(text: BroopActivitySource.label(row.source))
            if WorkoutSource.hasSuggestion(row) {
                BroopActivityChip(text: String(localized: "Suggested"), symbol: "sparkles")
            }
            Text(verbatim: Date(timeIntervalSince1970: TimeInterval(row.startTs)).formatted(date: .abbreviated, time: .omitted))
                .font(BroopType.demi(12))
                .foregroundStyle(BroopPalette.textSecondary)
        }
    }

    private var headline: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–")
                    .font(BroopType.number(62))
                    .broopNumeral(62, color: row.strain == nil ? BroopPalette.textSecondary : BroopPalette.effort)
                    .foregroundStyle(row.strain == nil ? BroopPalette.textSecondary : BroopPalette.effort)
                BroopCaps(String(localized: "Activity Effort"), size: 14, color: BroopPalette.textSecondary)
            }
            if WorkoutCatalog.isOnFoot(row.sport) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: steps.map { BroopActivityFormat.grouped(Double($0.count)) } ?? "–")
                        .font(BroopType.number(62))
                        .broopNumeral(62)
                        .foregroundStyle(steps == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    BroopCaps(steps.map { $0.fromStrap ? String(localized: "Steps · strap") : String(localized: "Steps · phone") }
                              ?? String(localized: "Activity steps"),
                              size: 14, color: BroopPalette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Heart-rate chart

    @ViewBuilder private var chart: some View {
        if hr.count > 1 {
            let values = hr.map(\.bpm)
            let lo = max(30, (values.min() ?? 60) - 10)
            let hi = (values.max() ?? 180) + 8
            let start = Date(timeIntervalSince1970: TimeInterval(row.startTs))
            let end = Date(timeIntervalSince1970: TimeInterval(max(row.endTs, row.startTs + 60)))
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(hr, id: \.ts) { b in
                        AreaMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(b.ts))),
                                 yStart: .value("Floor", lo), yEnd: .value("BPM", b.bpm))
                            .foregroundStyle(LinearGradient(colors: [Color(broopHex: 0x1E5A85).opacity(0.75), Color(broopHex: 0x1E5A85).opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(b.ts))), y: .value("BPM", b.bpm))
                            .foregroundStyle(Color(broopHex: 0x1E90E8))
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(x: .value("Start", start))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    RuleMark(x: .value("End", end))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: lo...hi)
                .chartXScale(domain: start.addingTimeInterval(-end.timeIntervalSince(start) * 0.04)...end.addingTimeInterval(end.timeIntervalSince(start) * 0.04))
                .clipped()
                .chartXAxis {
                    AxisMarks(values: [start, end]) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let n = v.as(Double.self) {
                                Text(verbatim: "\(Int(n))").font(BroopType.number(12)).foregroundStyle(BroopPalette.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 210)
                .accessibilityLabel(Text("Heart rate during \(WorkoutSource.displaySport(row.sport))"))
                HStack {
                    Text(verbatim: BroopActivityFormat.time(row.startTs))
                    Spacer()
                    Text(verbatim: BroopActivityFormat.time(row.endTs))
                }
                .font(BroopType.number(15))
                .foregroundStyle(BroopPalette.textPrimary)
                .padding(.horizontal, BroopMetrics.page)
                if editedAverage(traceMean: values.reduce(0, +) / Double(values.count)) {
                    Text("The average above was edited. The graph, zones and Effort stay from the recorded session.")
                        .font(BroopType.regular(12.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .padding(.horizontal, BroopMetrics.page)
                }
            }
        } else if loaded {
            Text("No heart-rate samples were recorded over this session's window.")
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
                .padding(.horizontal, BroopMetrics.page)
        }
    }

    /// The classic #18 rule: the row's Avg HR was edited away from what the recorded trace implies.
    private func editedAverage(traceMean: Double) -> Bool {
        guard let avg = row.avgHr, row.strain != nil || row.zonesJSON != nil else { return false }
        return abs(Double(avg) - traceMean) > 3
    }

    // MARK: Zones

    @ViewBuilder private var zones: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if zoneMinutes != nil {
                    BroopCaps(zonesFromImport ? String(localized: "WHOOP import") : String(localized: "From strap HR"),
                              size: 11, color: BroopPalette.textSecondary)
                }
                Spacer()
                BroopCaps(String(localized: "Duration"), size: 11, color: BroopPalette.textSecondary)
                Text(verbatim: BroopActivityFormat.hms(durationS))
                    .font(BroopType.number(16))
                    .foregroundStyle(BroopPalette.textPrimary)
            }
            if let z = zoneMinutes, z.reduce(0, +) > 0 {
                let total = z.reduce(0, +)
                ForEach((0..<5).reversed(), id: \.self) { i in
                    zoneRow(zone: i + 1, minutes: z[i], total: total)
                }
                Text(zonesFromImport
                     ? "WHOOP's imported per-zone split for this session."
                     : "Time in each %HRmax zone, derived from the strap's heart rate over this window (approximate).")
                    .font(BroopType.regular(13))
                    .foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func zoneRow(zone: Int, minutes: Double, total: Double) -> some View {
        let pct = minutes / max(total, 0.001)
        let active = minutes > 0.05
        let seconds = Int((minutes * 60).rounded())
        let range: String? = zonesFromImport ? nil : zoneRange(zone)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BroopCaps(String(localized: "Zone \(zone)"), size: 13)
                if let range { BroopCaps(range, size: 12, color: BroopPalette.textBody) }
                Text(verbatim: "\(Int((pct * 100).rounded()))%")
                    .font(BroopType.number(16))
                    .foregroundStyle(BroopActivityPalette.zone(zone))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "\(seconds / 3600):" + String(format: "%02d", (seconds % 3600) / 60))
                        .font(BroopType.number(22)).broopNumeral(22)
                    Text(verbatim: ":" + String(format: "%02d", seconds % 60))
                        .font(BroopType.number(15))
                        .foregroundStyle(BroopPalette.textSecondary)
                }
            }
            if active {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        BroopActivityHatch()
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BroopActivityPalette.zone(zone))
                            .frame(width: max(6, geo.size.width * pct))
                    }
                }
                .frame(height: 12)
            }
        }
        .opacity(active ? 1 : 0.4)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    private func zoneRange(_ zone: Int) -> String? {
        guard let z = profile.hrZoneSet.zones.first(where: { $0.number == zone }) else { return nil }
        if zone == 5 { return String(localized: "\(Int(z.lower))+ bpm") }
        return String(localized: "\(Int(z.lower))-\(Int(z.upper) - 1) bpm")
    }

    // MARK: Key statistics

    private var keyStatistics: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopCaps(String(localized: "Key statistics"), size: 13)
                .padding(.horizontal, BroopMetrics.page)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    BroopActivityStatCard(symbol: "flame", title: String(localized: "Calories"),
                                          value: row.energyKcal.map(BroopActivityFormat.grouped) ?? "–", unit: "cals")
                    BroopActivityStatCard(symbol: "heart", title: String(localized: "Avg HR"),
                                          value: row.avgHr.map(String.init) ?? "–", unit: "bpm")
                    BroopActivityStatCard(symbol: "arrow.up.heart", title: String(localized: "Max HR"),
                                          value: row.maxHr.map(String.init) ?? "–", unit: "bpm")
                    if let d = row.distanceM, d > 0 {
                        BroopActivityStatCard(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                              title: String(localized: "Distance"),
                                              value: UnitFormatter.distanceFromMeters(d, system: distanceSystem))
                        BroopActivityStatCard(symbol: "speedometer", title: String(localized: "Avg pace"), value: paceLabel)
                    }
                    if let low = hr.map(\.bpm).min(), hr.count > 1 {
                        BroopActivityStatCard(symbol: "arrow.down.heart", title: String(localized: "Low"),
                                              value: "\(Int(low.rounded()))", unit: "bpm")
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var paceLabel: String {
        guard let m = row.distanceM, m > 0, durationS > 0 else { return "–" }
        return UnitFormatter.paceFromSecPerKm(durationS / (m / 1000), system: distanceSystem)
    }

    // MARK: Heart-rate recovery

    @ViewBuilder private var recoverySection: some View {
        if let r = recovery {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BroopCaps(String(localized: "Heart rate recovery"), size: 13)
                    Spacer()
                    BroopCaps(String(localized: "Peak \(r.endHR) bpm"), size: 11, color: BroopPalette.textSecondary)
                }
                HStack(spacing: 10) {
                    recoveryCell(String(localized: "1 min"), r.after1Minute)
                    recoveryCell(String(localized: "2 min"), r.after2Minutes)
                    recoveryCell(String(localized: "5 min"), r.after5Minutes)
                }
                Text("The change from your heart rate at the end of exercise. Positive values mean your heart rate fell; a dash means the strap did not record enough data around that minute.")
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 30)
        }
    }

    private func recoveryCell(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BroopCaps(label, size: 10.5, color: BroopPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value.map { "\($0)" } ?? "–")
                    .font(BroopType.number(28)).broopNumeral(28, color: value.map { $0 >= 0 ? BroopPalette.teal : BroopPalette.warning } ?? BroopPalette.textSecondary)
                    .foregroundStyle(value.map { $0 >= 0 ? BroopPalette.teal : BroopPalette.warning } ?? BroopPalette.textSecondary)
                Text(verbatim: "bpm").font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: Route

    @ViewBuilder private var routeSection: some View {
        if route.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    WorkoutRouteMap(points: route)
                        .frame(height: 240)
                        .accessibilityLabel(Text("Map of your \(WorkoutSource.displaySport(row.sport)) route"))
                    BroopCaps(String(localized: "Route"), size: 12)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .padding(12)
                    VStack {
                        Spacer()
                        HStack(spacing: 0) {
                            routeStat(row.distanceM.map { UnitFormatter.distanceFromMeters($0, system: distanceSystem) } ?? "–",
                                      String(localized: "Distance"))
                            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 30)
                            routeStat(paceLabel, String(localized: "Avg pace"))
                            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 30)
                            routeStat("\(route.count)", String(localized: "Points"))
                        }
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(routeDescription)
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(BroopPalette.textSecondary)
                BroopActivityButton(title: String(localized: "Export route"), symbol: "square.and.arrow.up", kind: .grey, height: 48) {
                    exportingRoute = true
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.top, 30)
        }
    }

    private func routeStat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(BroopType.number(17)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            BroopCaps(title, size: 9, color: BroopPalette.textBody)
        }
        .frame(maxWidth: .infinity)
    }

    private var routeDescription: String {
        switch WorkoutSource.classify(row.source) {
        case .apple, .whoop, .lifting, .activityFile:
            return String(localized: "This stays on your device. It is never uploaded, never synced, never shared.")
        case .detected, .manual:
            return String(localized: "Your GPS route for this session, recorded and stored on your device. Nothing leaves your phone.")
        }
    }

    @MainActor private func exportRoute(_ format: RouteExporter.Format) {
        guard route.count >= 2 else { return }
        let points = route.map { RoutePoint(lat: $0.lat, lon: $0.lon) }
        let name = "noop-route-\(row.startTs).\(format.ext)"
        let r = row
        Task.detached(priority: .userInitiated) {
            let data = RouteExporter.render(format, route: points, startTs: r.startTs, endTs: r.endTs, sport: r.sport,
                                            distanceM: r.distanceM, energyKcal: r.energyKcal, avgHr: r.avgHr, maxHr: r.maxHr)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do { try data.write(to: url) } catch { return }
            await MainActor.run { FileExport.exportFile(at: url, suggestedName: name) }
        }
    }

    // MARK: Load (the classic WorkoutDetailView load, unchanged)

    private func load() async {
        let routePoints: [RouteMath.LatLng] = {
            guard let r = RouteStore.load(startTs: row.startTs, sport: row.sport) else { return [] }
            let pts = RouteMath.decode(r.polyline)
            return pts.count >= 2 ? pts : []
        }()
        let buckets = await repo.workoutHrBuckets(from: row.startTs, to: row.endTs, source: row.source)
        var minutes: [Double]?
        var fromImport = false
        if let pct = WorkoutZones.percents(row.zonesJSON) {
            let durMin = (row.durationS ?? Double(row.endTs - row.startTs)) / 60.0
            if durMin > 0 {
                minutes = pct.map { durMin * $0 / 100.0 }
                fromImport = true
            }
        }
        if minutes == nil {
            minutes = await repo.workoutZoneMinutes(from: row.startTs, to: row.endTs, zoneSet: profile.hrZoneSet, source: row.source)
        }
        let hrr = await repo.workoutHeartRateRecovery(from: row.startTs, to: row.endTs, maxHR: Double(profile.hrMax), source: row.source)
        var stepReadout: (count: Int, fromStrap: Bool)?
        if WorkoutCatalog.isOnFoot(row.sport) {
            if let ticks = await repo.strapStepTicks(from: row.startTs, to: row.endTs) {
                let scaled = Int((Double(ticks) / max(profile.stepTicksPerStep, 0.5)).rounded())
                if scaled > 0 { stepReadout = (scaled, true) }
            }
            if stepReadout == nil, let ped = await WorkoutPedometer.steps(fromSec: row.startTs, toSec: row.endTs), ped > 0 {
                stepReadout = (ped, false)
            }
        }
        route = routePoints
        hr = buckets
        zoneMinutes = minutes
        zonesFromImport = fromImport
        recovery = hrr
        steps = stepReadout
        loaded = true
    }
}

/// WHOOP's diagonal-hatched track behind a zone bar.
struct BroopActivityHatch: View {
    var body: some View {
        Canvas { ctx, size in
            let rect = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4)
            ctx.fill(rect, with: .color(Color(broopHex: 0x2F3337)))
            ctx.clip(to: rect)
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(BroopActivityPalette.hatch), lineWidth: 2.5)
                x += 7
            }
        }
    }
}
#endif
