#if os(iOS)
import Charts
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A tapped workout, as a navigation value. Identity is the natural key the store uses.
struct BroopActivityDetailTarget: Hashable {
    let row: WorkoutRow
    var id: String { "\(row.startTs)|\(row.sport)|\(row.source)" }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Activities: every session, WHOOP-style, over the `WorkoutsView` model. The log tab lists
/// sessions by day with the range, sport, source and search filters, the Current / Archived split and
/// multi-select merge and delete. The insights tab carries the summaries: typical Effort, totals,
/// the active-calorie heatmap, the per-sport breakdown, imported HR zones and the heart-rate recovery
/// trend. Adding, editing, relabelling, dismissing, deleting and duplicating a session go through the
/// same `Repository` calls the screen makes.
struct BroopActivityListView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue

    enum Tab: Hashable { case log, insights }
    enum Range: CaseIterable, Hashable {
        case week, month, quarter, year, all
        var label: String {
            switch self {
            case .week: return String(localized: "7D")
            case .month: return String(localized: "30D")
            case .quarter: return String(localized: "90D")
            case .year: return String(localized: "1Y")
            case .all: return String(localized: "All")
            }
        }
        var caption: String {
            switch self {
            case .week: return String(localized: "last 7 days")
            case .month: return String(localized: "last 30 days")
            case .quarter: return String(localized: "last 90 days")
            case .year: return String(localized: "last year")
            case .all: return String(localized: "all time")
            }
        }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
        var widening: [Range] {
            let order: [Range] = [.week, .month, .quarter, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    @State private var tab: Tab = .log
    @State private var allRows: [WorkoutRow] = []
    @State private var loaded = false
    @State private var loadedWindowDays: Int? = WorkoutRules.firstPaintWindowDays
    @State private var range: Range = .all
    @State private var seededRange = false
    @State private var scope: WorkoutRules.Scope = .current
    @State private var sportFilter: String?
    @State private var sourceFilter: WorkoutSource?
    @State private var searchText = ""
    @State private var selectionMode = false
    @State private var selected: Set<String> = []
    @State private var dailyKcal: [String: Double] = [:]
    @State private var recoveryTrend: [(startTs: Int, result: HeartRateRecovery.Result)] = []
    @State private var postLogNote: String?

    @State private var editTarget: EditTarget?
    @State private var detail: BroopActivityDetailTarget?
    @State private var startCover = false
    @State private var mergePrompt: MergeTarget?

    private struct EditTarget: Identifiable {
        let editing: WorkoutRow?
        var isCopy = false
        let id = UUID()
    }
    private struct MergeTarget: Identifiable {
        let rows: [WorkoutRow]
        let id = UUID()
    }

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }
    private var filter: WorkoutFilter { WorkoutFilter(sport: sportFilter, sourceClass: sourceFilter, search: searchText) }
    private var latestTs: Int? { allRows.map(\.startTs).max() }

    var body: some View {
        let resolved = effectiveRange
        let unscoped = sessions(for: resolved)
        let rows = WorkoutRules.scopedRows(unscoped, scope: scope)
        let trendRows = recoveryTrendRows(from: unscoped)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                actionButtons.padding(.top, 10)
                BroopActivityDetectedCard().padding(.top, 12)
                if let postLogNote {
                    BroopActivityNotice(symbol: "chart.line.uptrend.xyaxis", text: postLogNote, tint: BroopPalette.effort)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                BroopUnderlineTabs(options: [Tab.log, Tab.insights], selection: $tab) {
                    $0 == .log ? String(localized: "Activities") : String(localized: "Insights")
                }
                .padding(.top, 24)

                rangePills(resolved: resolved, rows: rows).padding(.top, 18)

                if !loaded {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if allRows.isEmpty {
                    emptyState.padding(.top, 20)
                } else if tab == .log {
                    logTab(rows: rows)
                } else {
                    insightsTab(rows: rows, resolved: resolved)
                }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopActivityHeader(title: String(localized: "Activities"), inBar: true, onBack: { dismiss() }) {
                if tab == .log, rows.contains(where: WorkoutMerge.isMergeable) {
                    Button(selectionMode ? String(localized: "Done") : String(localized: "Select")) {
                        withAnimation(.snappy) {
                            selectionMode.toggle()
                            if !selectionMode { selected.removeAll() }
                        }
                    }
                    .font(BroopType.demi(15))
                    .foregroundStyle(BroopPalette.textPrimary)
                }
            }
        }
        .broopActivityPage()
        .refreshable { await repo.refresh() }
        .task(id: repo.refreshSeq) { await load() }
        .task(id: recoveryKey(trendRows)) { await loadRecoveryTrend(trendRows) }
        .onAppear { consumePendingRoute() }
        .onChange(of: router.pendingWorkout) { _, _ in consumePendingRoute() }
        .onChange(of: allRows) { _, _ in consumePendingRoute() }
        .onChange(of: range) { _, newRange in
            Task { await expandWindowIfNeeded(newRange == .all ? .all : effectiveRange) }
        }
        .navigationDestination(item: $detail) { target in
            BroopActivityDetailView(row: target.row, actions: actions)
        }
        .sheet(item: $editTarget) { target in
            BroopActivityEditSheet(editing: target.editing, isCopy: target.isCopy) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: target.isCopy ? nil : replacing)
                    await intelligence.analyzeRecent()
                    await reload()
                    await showPostLogNote(WorkoutSource.displaySport(row.sport))
                }
            }
        }
        .fullScreenCover(isPresented: $startCover) {
            BroopActivityStartCover(onClose: { startCover = false })
        }
        .fullScreenCover(item: $mergePrompt) { target in
            BroopActivityTypePicker(title: String(localized: "Name the merged session"),
                                    subtitle: String(localized: "These sessions have no sport label yet."),
                                    recordsRecent: false) { name in
                performMerge(target.rows, sport: name)
            }
        }
    }

    // MARK: Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            BroopActivityButton(title: String(localized: "Add activity"), symbol: "plus", kind: .grey, height: 50) {
                editTarget = EditTarget(editing: nil)
            }
            BroopActivityStartControl { startCover = true }
        }
    }

    var actions: BroopActivityRowActions {
        BroopActivityRowActions(
            edit: { editTarget = EditTarget(editing: $0) },
            duplicate: { editTarget = EditTarget(editing: manualCopy($0), isCopy: true) },
            relabel: { row, sport in
                Task {
                    await repo.relabelDetected(row, sport: sport)
                    await reload()
                    await showPostLogNote(WorkoutSource.displaySport(sport))
                }
            },
            dismissDetected: { row in Task { await repo.dismissDetected(row); await reload() } },
            delete: { row in
                RouteStore.remove(startTs: row.startTs, sport: row.sport)
                Task { await repo.deleteWorkout(row); await reload() }
            })
    }

    private func manualCopy(_ row: WorkoutRow) -> WorkoutRow {
        WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: WorkoutSource.displaySport(row.sport),
                   source: "manual", durationS: row.durationS, energyKcal: row.energyKcal,
                   avgHr: row.avgHr, maxHr: row.maxHr, strain: row.strain, distanceM: row.distanceM,
                   zonesJSON: row.zonesJSON, notes: row.notes, steps: row.steps,
                   suggestedClass: nil, suggestedClassConfidence: nil)
    }

    // MARK: Range and filters

    private func rangePills(resolved: Range, rows: [WorkoutRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Range.allCases, id: \.self) { r in
                    Button { withAnimation(.snappy) { range = r } } label: {
                        Text(verbatim: r.label)
                            .font(r == range ? BroopType.caps(12) : BroopType.demi(12))
                            .foregroundStyle(r == range ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(r == range ? Color(broopHex: 0x2C3136) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(broopHex: 0x151618)))
            Text(verbatim: rangeCaption(rows: rows, resolved: resolved))
                .font(BroopType.demi(12))
                .foregroundStyle(resolved != range ? BroopPalette.warning : BroopPalette.textSecondary)
        }
    }

    private func rangeCaption(rows: [WorkoutRow], resolved: Range) -> String {
        guard loaded, !allRows.isEmpty else { return "–" }
        let n = rows.count
        let suffix = filter.isActive ? String(localized: " · filtered") : ""
        if resolved != range {
            return (n == 1 ? String(localized: "1 session · sparse, widened to \(resolved.caption)")
                           : String(localized: "\(n) sessions · sparse, widened to \(resolved.caption)")) + suffix
        }
        return (n == 1 ? String(localized: "1 session · \(resolved.caption)")
                       : String(localized: "\(n) sessions · \(resolved.caption)")) + suffix
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                filterMenu(sportFilter ?? String(localized: "All sports"), active: sportFilter != nil) {
                    Button(String(localized: "All sports")) { sportFilter = nil }
                    Divider()
                    ForEach(availableSports, id: \.self) { s in Button(s) { sportFilter = s } }
                }
                filterMenu(sourceFilter.map(BroopActivitySource.short) ?? String(localized: "All sources"), active: sourceFilter != nil) {
                    Button(String(localized: "All sources")) { sourceFilter = nil }
                    Divider()
                    ForEach([WorkoutSource.whoop, .apple, .detected, .manual, .lifting, .activityFile], id: \.self) { c in
                        Button(BroopActivitySource.short(c)) { sourceFilter = c }
                    }
                }
            }
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BroopPalette.textSecondary)
                    TextField(String(localized: "Search sport"), text: $searchText)
                        .font(BroopType.regular(15))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(broopHex: 0x2A2E33)))
                if filter.isActive {
                    Button {
                        withAnimation(.snappy) { sportFilter = nil; sourceFilter = nil; searchText = "" }
                    } label: {
                        BroopCaps(String(localized: "Clear"), size: 10.5, color: BroopPalette.textSecondary)
                            .frame(height: 40)
                            .padding(.horizontal, 6)
                    }
                    .accessibilityLabel(Text("Clear filters"))
                }
            }
        }
    }

    private func filterMenu<Content: View>(_ title: String, active: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 6) {
                BroopCaps(title, size: 10.5, color: active ? BroopPalette.textPrimary : BroopPalette.textBody)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? BroopPalette.effort.opacity(0.25) : BroopActivityPalette.chip))
        }
    }

    private var availableSports: [String] {
        var counts: [String: Int] = [:]
        for r in allRows { counts[WorkoutSource.displaySport(r.sport), default: 0] += 1 }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    // MARK: Log tab

    @ViewBuilder
    private func logTab(rows: [WorkoutRow]) -> some View {
        filterBar.padding(.top, 14)
        HStack(spacing: 18) {
            ForEach(WorkoutRules.Scope.allCases) { s in
                Button { withAnimation(.snappy) { scope = s } } label: {
                    BroopCaps(s == .current ? String(localized: "Recent 10") : String(localized: "Archived"), size: 10.5,
                              color: scope == s ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            if scope == s { Rectangle().fill(Color.white).frame(height: 2).offset(y: 3) }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 18)

        if selectionMode { selectionToolbar(rows: rows).padding(.top, 12) }

        if rows.isEmpty {
            Text(scope == .archived
                 ? String(localized: "Nothing archived yet. Sessions older than your 10 most recent move here, and stay on your phone.")
                 : String(localized: "No sessions match these filters."))
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textSecondary)
                .padding(.vertical, 24)
        }

        let days = groupedByDay(rows)
        ForEach(days, id: \.key) { day in
            BroopActivityDivider(title: day.label).padding(.top, 22).padding(.bottom, 10)
            ForEach(day.rows, id: \.startTs) { row in
                logRow(row).padding(.bottom, 8)
            }
        }
    }

    private func groupedByDay(_ rows: [WorkoutRow]) -> [(key: String, label: String, rows: [WorkoutRow])] {
        let sorted = rows.sorted { $0.startTs > $1.startTs }
        var out: [(key: String, label: String, rows: [WorkoutRow])] = []
        let cal = Calendar.current
        for r in sorted {
            let d = Date(timeIntervalSince1970: TimeInterval(r.startTs))
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            if out.last?.key == key { out[out.count - 1].rows.append(r) }
            else { out.append((key, BroopActivityFormat.dayLabel(r.startTs), [r])) }
        }
        return out
    }

    private func selectionKey(_ row: WorkoutRow) -> String { "\(row.startTs)|\(row.sport)" }

    private func logRow(_ row: WorkoutRow) -> some View {
        let selectable = WorkoutMerge.isMergeable(row)
        let isSelected = selected.contains(selectionKey(row))
        return Button {
            if selectionMode {
                guard selectable else { return }
                if isSelected { selected.remove(selectionKey(row)) } else { selected.insert(selectionKey(row)) }
            } else {
                detail = BroopActivityDetailTarget(row: row)
            }
        } label: {
            HStack(spacing: 12) {
                if selectionMode {
                    Image(systemName: selectable ? (isSelected ? "checkmark.circle.fill" : "circle") : "lock.fill")
                        .font(.system(size: selectable ? 20 : 13))
                        .foregroundStyle(isSelected ? BroopPalette.effort : BroopPalette.textTertiary)
                        .frame(width: 22)
                }
                BroopActivityPill(sport: row.sport,
                                  value: row.strain.map { UnitFormatter.effortDisplay($0, scale: effortScale) } ?? "–",
                                  color: row.strain == nil ? BroopActivityPalette.chip : BroopActivityPalette.strainBlue,
                                  width: selectionMode ? 80 : 94)
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(WorkoutSource.displaySport(row), size: 12).lineLimit(1)
                    Text(verbatim: rowSubtitle(row))
                        .font(BroopType.demi(11.5))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(verbatim: BroopActivityFormat.time(row.startTs))
                    if row.endTs > row.startTs { Text(verbatim: BroopActivityFormat.time(row.endTs)) }
                }
                .font(BroopType.demi(12))
                .foregroundStyle(BroopPalette.textBody)
                VStack(spacing: 0) {
                    Circle().fill(BroopPalette.textPrimary).frame(width: 2.5, height: 2.5)
                    Rectangle().fill(row.strain == nil ? BroopPalette.textTertiary : BroopPalette.effort).frame(width: 2)
                    Circle().fill(BroopPalette.textPrimary).frame(width: 2.5, height: 2.5)
                }
                .frame(height: 28)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius + 2, style: .continuous).fill(BroopPalette.row))
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .contextMenu { if !selectionMode { actions.menu(for: row) } }
        .accessibilityHint(Text(selectionMode ? "Double-tap to select" : "Opens activity detail"))
    }

    private func rowSubtitle(_ row: WorkoutRow) -> String {
        var parts: [String] = []
        if let d = row.durationS, d > 0 { parts.append(BroopActivityFormat.shortDuration(d)) }
        if let hr = row.avgHr { parts.append(String(localized: "\(hr) bpm")) }
        if let m = row.distanceM, m > 0 { parts.append(UnitFormatter.distanceFromMeters(m, system: distanceSystem)) }
        parts.append(BroopActivitySource.short(WorkoutSource.classify(row.source)))
        if WorkoutSource.hasSuggestion(row) { parts.append(String(localized: "suggested")) }
        return parts.joined(separator: " · ")
    }

    private func selectionToolbar(rows: [WorkoutRow]) -> some View {
        let chosen = rows.filter { selected.contains(selectionKey($0)) }
        let canMerge = WorkoutMerge.canMerge(chosen)
        return HStack(spacing: 10) {
            BroopActivityButton(title: String(localized: "Merge (\(chosen.count))"), symbol: "arrow.triangle.merge", kind: .grey, height: 42) {
                beginMerge(chosen)
            }
            .disabled(!canMerge)
            BroopActivityButton(title: String(localized: "Delete (\(chosen.count))"), symbol: "trash", kind: .destructive, height: 42) {
                let toDelete = chosen
                selectionMode = false; selected.removeAll()
                Task { await repo.bulkDeleteWorkouts(toDelete); await reload() }
            }
            .disabled(chosen.isEmpty)
        }
    }

    private func beginMerge(_ chosen: [WorkoutRow]) {
        guard WorkoutMerge.canMerge(chosen) else { return }
        if WorkoutMerge.resolvedSport(chosen) == nil { mergePrompt = MergeTarget(rows: chosen) }
        else { performMerge(chosen, sport: nil) }
    }

    private func performMerge(_ chosen: [WorkoutRow], sport: String?) {
        guard let merged = WorkoutMerge.merge(chosen, sport: sport) else { return }
        selectionMode = false; selected.removeAll(); mergePrompt = nil
        Task {
            await repo.mergeWorkouts(chosen, into: merged)
            await intelligence.analyzeRecent()
            await reload()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopCaps(String(localized: "No activities yet"), size: 12)
            Text("They come from your WHOOP and Apple Health history. Import in Data Sources to bring them in, start one live, or add one you tracked elsewhere.")
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }

    // MARK: Insights tab

    @ViewBuilder
    private func insightsTab(rows: [WorkoutRow], resolved: Range) -> some View {
        let groups = sportGroups(rows)
        let strains = rows.compactMap(\.strain)
        let avg = strains.isEmpty ? nil : strains.reduce(0, +) / Double(strains.count)
        let totalH = rows.compactMap(\.durationS).reduce(0, +) / 3600
        let kcal = rows.compactMap(\.energyKcal).reduce(0, +)
        let dist = rows.compactMap(\.distanceM).filter { $0 > 0 }

        HStack(spacing: 20) {
            BroopDial(score: .effort, value: avg.map { UnitFormatter.effortValue($0, scale: effortScale) },
                      maxValue: effortScale == .whoop ? 21 : 100, diameter: 112, lineWidth: 7)
            VStack(alignment: .leading, spacing: 6) {
                BroopCaps(String(localized: "Typical Effort"), size: 11, color: BroopPalette.textSecondary)
                Text(groups.first.map { "Mostly \(WorkoutSource.displaySport($0.sport)) (\(resolved.caption))." }
                     ?? "Logged sessions across \(resolved.caption).")
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 22)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile(String(localized: "Workouts"), "\(rows.count)", resolved.caption)
            tile(String(localized: "Total time"), String(format: "%.1f", totalH), String(localized: "hours active"))
            tile(String(localized: "Calories"), BroopActivityFormat.grouped(kcal), "kcal")
            tile(String(localized: "Distance"),
                 dist.isEmpty ? "–" : UnitFormatter.distanceFromKilometers(dist.reduce(0, +) / 1000, system: distanceSystem),
                 String(localized: "covered"))
        }
        .padding(.top, 20)

        heatmap.padding(.top, 30)

        if !groups.isEmpty {
            BroopSectionTitle(String(localized: "By sport")).padding(.top, 30).padding(.bottom, 12)
            ForEach(groups, id: \.sport) { g in
                sportRow(g, zones: WorkoutZones.summary(from: rows.filter { $0.sport == g.sport }))
                    .padding(.bottom, 8)
            }
        }

        if let z = WorkoutZones.summary(from: rows) {
            BroopSectionTitle(String(localized: "Heart rate zones")).padding(.top, 26).padding(.bottom, 12)
            zonesCard(z, total: rows.count)
        }

        if !recoveryTrend.isEmpty {
            BroopSectionTitle(String(localized: "Recovery trend")).padding(.top, 26).padding(.bottom, 12)
            recoveryTrendCard
        }
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(28)).broopNumeral(28)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: caption).font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }

    @ViewBuilder private var heatmap: some View {
        let today = Self.dayKey(Date())
        let grid = ActivityHeatmap.build(values: dailyKcal, today: today)
        if !grid.isEmpty {
            BroopCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        BroopCaps(String(localized: "Active calories"), size: 11)
                        Spacer()
                        BroopCaps(String(localized: "Last 13 weeks"), size: 10, color: BroopPalette.textSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: BroopActivityFormat.grouped(grid.total)).font(BroopType.number(26)).broopNumeral(26)
                        Text(verbatim: "kcal").font(BroopType.demi(13)).foregroundStyle(BroopPalette.textSecondary)
                        Spacer()
                        if grid.streak > 0 {
                            Text(verbatim: "\(grid.streak)").font(BroopType.number(17)).foregroundStyle(BroopPalette.effort)
                            Text(grid.streak == 1 ? "day in a row" : "days in a row")
                                .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
                        }
                    }
                    Canvas { ctx, size in
                        let cols = grid.columns.count
                        guard cols > 0 else { return }
                        let gap: CGFloat = 3
                        let cell = min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * 6) / 7)
                        for c in 0..<cols {
                            for r in 0..<7 {
                                let rect = CGRect(x: CGFloat(c) * (cell + gap), y: CGFloat(r) * (cell + gap), width: cell, height: cell)
                                let p = Path(roundedRect: rect, cornerRadius: cell * 0.22)
                                ctx.fill(p, with: .color(Self.heat(grid.columns[c][r].level)))
                                if grid.columns[c][r].day == today {
                                    ctx.stroke(p, with: .color(.white), lineWidth: 1.2)
                                }
                            }
                        }
                    }
                    .aspectRatio(13.0 / 7.0, contentMode: .fit)
                    .accessibilityLabel(Text("Active-calorie heatmap, last 13 weeks"))
                    HStack(spacing: 4) {
                        Text("Less").font(BroopType.demi(11)).foregroundStyle(BroopPalette.textSecondary)
                        ForEach(0..<5, id: \.self) { l in
                            RoundedRectangle(cornerRadius: 2).fill(Self.heat(l)).frame(width: 10, height: 10)
                        }
                        Text("More").font(BroopType.demi(11)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
            }
        }
    }

    private static func heat(_ level: Int) -> Color {
        switch level {
        case 0: return BroopPalette.track
        case 1: return BroopPalette.effort.opacity(0.3)
        case 2: return BroopPalette.effort.opacity(0.55)
        case 3: return BroopPalette.effort.opacity(0.8)
        default: return BroopPalette.effort
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dayKey(_ d: Date) -> String { dayFormatter.string(from: d) }

    private struct SportGroup {
        let sport: String
        let count: Int
        let time: Double
        let kcal: Double
    }

    private func sportGroups(_ rows: [WorkoutRow]) -> [SportGroup] {
        var acc: [String: (Int, Double, Double)] = [:]
        for r in rows {
            var a = acc[r.sport] ?? (0, 0, 0)
            a.0 += 1; a.1 += r.durationS ?? 0; a.2 += r.energyKcal ?? 0
            acc[r.sport] = a
        }
        return acc.map { SportGroup(sport: $0.key, count: $0.value.0, time: $0.value.1, kcal: $0.value.2) }
            .sorted { ($0.count, $0.time) > ($1.count, $1.time) }
    }

    private func sportRow(_ g: SportGroup, zones: WorkoutZones.Summary?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WorkoutTypeIcon(workoutType: g.sport, size: 22, weight: .semibold, color: .white)
                BroopCaps(WorkoutSource.displaySport(g.sport), size: 12).lineLimit(1)
                Spacer()
                Text(verbatim: "\(g.count)").font(BroopType.number(20)).foregroundStyle(BroopPalette.effort)
            }
            if let zones { zoneStack(zones.minutes, height: 8) }
            HStack(spacing: 0) {
                mini(String(localized: "Sessions"), "\(g.count)")
                mini(String(localized: "Time"), String(format: "%.1fh", g.time / 3600))
                mini(String(localized: "Kcal"), BroopActivityFormat.grouped(g.kcal))
                mini(String(localized: "Avg"), "\(Int((g.count > 0 ? g.time / Double(g.count) / 60 : 0).rounded()))m")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }

    private func mini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BroopCaps(title, size: 9, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(16)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zoneStack(_ minutes: [Double], height: CGFloat) -> some View {
        let total = max(minutes.reduce(0, +), 0.001)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle().fill(BroopActivityPalette.zone(i + 1))
                        .frame(width: max(0, geo.size.width * minutes[i] / total))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func zonesCard(_ z: WorkoutZones.Summary, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            zoneStack(z.minutes, height: 16)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(BroopActivityPalette.zone(i + 1)).frame(width: 8, height: 8)
                            BroopCaps("Z\(i + 1)", size: 9.5, color: BroopPalette.textSecondary)
                        }
                        Text(verbatim: "\(Int((z.minutes[i] / max(z.totalMinutes, 0.001) * 100).rounded()))%")
                            .font(BroopType.number(16))
                        Text(verbatim: BroopActivityFormat.shortDuration(z.minutes[i] * 60))
                            .font(BroopType.demi(11)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(verbatim: String(localized: "\(z.sessionsWithZones) of \(total) sessions") + " · " +
                 String(localized: "Share of imported zone time, duration-weighted across sessions (approximate)."))
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }

    private var recoveryTrendCard: some View {
        struct Plot: Identifiable { let date: Date; let interval: String; let value: Int; var id: String { "\(interval)\(date)" } }
        let one = String(localized: "1 min"), two = String(localized: "2 min"), five = String(localized: "5 min")
        let plots: [Plot] = recoveryTrend.flatMap { p -> [Plot] in
            let d = Date(timeIntervalSince1970: TimeInterval(p.startTs))
            return [p.result.after1Minute.map { Plot(date: d, interval: one, value: $0) },
                    p.result.after2Minutes.map { Plot(date: d, interval: two, value: $0) },
                    p.result.after5Minutes.map { Plot(date: d, interval: five, value: $0) }].compactMap { $0 }
        }
        return VStack(alignment: .leading, spacing: 12) {
            Chart(plots) { p in
                LineMark(x: .value("Workout", p.date), y: .value("Recovery", p.value))
                    .foregroundStyle(by: .value("Interval", p.interval))
                PointMark(x: .value("Workout", p.date), y: .value("Recovery", p.value))
                    .foregroundStyle(by: .value("Interval", p.interval))
                    .symbolSize(24)
            }
            .chartForegroundStyleScale(domain: [one, two, five], range: [BroopPalette.teal, BroopPalette.effort, Color(broopHex: 0xB07CFF)])
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(BroopPalette.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(BroopPalette.hairline)
                    AxisValueLabel().foregroundStyle(BroopPalette.textSecondary)
                }
            }
            .frame(height: 190)
            Text("Each line shows how many beats per minute your heart rate changed after exercise. Only high-intensity workouts with recorded post-workout heart rate are included.")
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius).fill(BroopPalette.card))
    }

    // MARK: Data (the WorkoutsView rules)

    private func sessions(for r: Range) -> [WorkoutRow] {
        let windowed: [WorkoutRow]
        if let days = r.days {
            guard let last = latestTs else { return [] }
            windowed = allRows.filter { $0.startTs >= last - days * 86_400 }
        } else {
            windowed = allRows
        }
        return filter.apply(windowed)
    }

    private var effectiveRange: Range {
        guard !allRows.isEmpty else { return range }
        for r in range.widening where !sessions(for: r).isEmpty { return r }
        return .all
    }

    private func defaultRange(_ source: [WorkoutRow]) -> Range {
        guard let last = source.map(\.startTs).max() else { return .all }
        for r in Range.allCases where r.days != nil {
            if source.filter({ $0.startTs >= last - (r.days ?? 0) * 86_400 }).count >= 2 { return r }
        }
        return .all
    }

    private func load() async {
        let r = await repo.workoutRows(days: loadedWindowDays ?? 4000)
        allRows = r
        if !loaded {
            loaded = true
            if !seededRange { range = defaultRange(r); seededRange = true }
        }
        let from = Calendar.current.date(byAdding: .day, value: -100, to: Date()) ?? Date()
        let metrics = await repo.dailyMetrics(fromDay: Self.dayKey(from), toDay: Self.dayKey(Date()))
        dailyKcal = Dictionary(metrics.compactMap { m in m.activeKcalEst.map { (m.day, $0) } }, uniquingKeysWith: max)
    }

    private func reload() async { allRows = await repo.workoutRows(days: loadedWindowDays ?? 4000) }

    private func expandWindowIfNeeded(_ picked: Range) async {
        guard loadedWindowDays != nil else { return }
        if let d = picked.days, d <= (loadedWindowDays ?? 0) { return }
        loadedWindowDays = nil
        allRows = await repo.workoutRows(days: 4000)
    }

    private func recoveryTrendRows(from unscoped: [WorkoutRow]) -> [WorkoutRow] {
        guard let last = latestTs else { return [] }
        return unscoped.filter { $0.startTs >= last - 90 * 86_400 }.sorted { $0.startTs < $1.startTs }
    }

    private func recoveryKey(_ rows: [WorkoutRow]) -> String {
        "\(repo.refreshSeq)|\(profile.hrMax)|" + rows.map { "\($0.startTs):\($0.endTs)" }.joined(separator: ",")
    }

    private func loadRecoveryTrend(_ rows: [WorkoutRow]) async {
        var built: [(startTs: Int, result: HeartRateRecovery.Result)] = []
        for row in rows {
            if Task.isCancelled { return }
            if let r = await repo.workoutHeartRateRecovery(from: row.startTs, to: row.endTs,
                                                           maxHR: Double(profile.hrMax), source: row.source) {
                built.append((row.startTs, r))
            }
        }
        guard !Task.isCancelled else { return }
        recoveryTrend = built
    }

    private func showPostLogNote(_ sport: String) async {
        let costs = InsightsRules.computeActivityCosts(workouts: allRows, days: repo.days)
        guard let match = costs.first(where: { $0.sport == sport }) else { postLogNote = nil; return }
        let sentence = match.sentence()
        withAnimation(.easeOut(duration: 0.2)) { postLogNote = sentence }
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        if postLogNote == sentence { withAnimation(.easeOut(duration: 0.2)) { postLogNote = nil } }
    }

    /// A detected-workout notification lands here through `router.pendingWorkout`: find the row that
    /// OVERLAPS the notified span (re-detection drifts boundaries), preferring a detected row, then open
    /// its detail or edit sheet. Same rule as the screen.
    private func consumePendingRoute() {
        guard let pending = router.pendingWorkout, loaded else { return }
        let overlapping = allRows.filter { $0.startTs < pending.endTs && pending.startTs < $0.endTs }
        let row = overlapping.first(where: { WorkoutSource.classify($0.source) == .detected })
            ?? overlapping.max(by: { $0.endTs < $1.endTs })
        router.pendingWorkout = nil
        guard let row else { return }
        switch pending {
        case .detail: detail = BroopActivityDetailTarget(row: row)
        case .edit: editTarget = EditTarget(editing: row)
        }
    }
}

/// START ACTIVITY, or RETURN TO ACTIVITY while one runs. Its own view so the list does not observe
/// `AppModel`, which publishes every heartbeat.
private struct BroopActivityStartControl: View {
    @EnvironmentObject private var model: AppModel
    let open: () -> Void

    var body: some View {
        let active = model.activeWorkout != nil
        BroopActivityButton(title: active ? String(localized: "Open activity") : String(localized: "Start activity"),
                            symbol: active ? "record.circle" : "stopwatch", kind: .grey, height: 50, action: open)
            .overlay(alignment: .topTrailing) {
                if active { Circle().fill(BroopPalette.bandLow).frame(width: 8, height: 8).padding(8) }
            }
    }
}

/// The auto-detected workout suggestion (`AutoWorkoutCard` behaviour), when the opt-in
/// "Auto-detect workouts" toggle is on: Save creates the workout, Not a workout dismisses it for good.
struct BroopActivityDetectedCard: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(PuffinExperiment.autoDetectWorkoutsKey) private var enabled = false
    @State private var candidate: DetectedWorkout?
    @State private var handled = false
    @State private var saving = false

    var body: some View {
        Group {
            if enabled, !handled, let w = candidate {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Color(broopHex: 0x8B6CF0))
                        BroopCaps(String(localized: "Looks like a workout"), size: 11)
                        Spacer()
                    }
                    Text(verbatim: prompt(w))
                        .font(BroopType.medium(15))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        BroopActivityButton(title: String(localized: "Save it"), kind: .filled, height: 42) { save(w) }
                            .disabled(saving)
                        BroopActivityButton(title: String(localized: "Not a workout"), kind: .grey, height: 42) { dismissIt(w) }
                            .disabled(saving)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color(broopHex: 0x6B5FC7))
                )
            }
        }
        .task(id: "\(repo.refreshSeq)-\(enabled)") {
            guard enabled else { candidate = nil; return }
            let next = await repo.autoDetectCandidate()
            if next != candidate { handled = false }
            candidate = next
        }
    }

    private func prompt(_ w: DetectedWorkout) -> String {
        let startDate = Date(timeIntervalSince1970: TimeInterval(w.startSec))
        let fmt = AppClock.hourMinuteFormatter()
        let start = fmt.string(from: startDate)
        let end = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(w.endSec)))
        let cal = Calendar.current
        if cal.isDateInToday(startDate) {
            return String(localized: "Looks like a workout around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
        }
        if cal.isDateInYesterday(startDate) {
            return String(localized: "Looks like a workout yesterday around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
        }
        let day = startDate.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Looks like a workout on \(day) around \(start)-\(end) (avg HR \(w.avgBpm), \(w.durationMin) min). Save it?")
    }

    private func save(_ w: DetectedWorkout) {
        saving = true
        handled = true
        Task {
            _ = await repo.saveDetectedWorkout(w)
            await repo.refresh()
            saving = false
        }
    }

    private func dismissIt(_ w: DetectedWorkout) {
        repo.dismissDetectedSuggestion(w)
        handled = true
        candidate = nil
    }
}
#endif
