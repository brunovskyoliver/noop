#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import StrandImport
import WhoopStore

/// Broop Lab Book (`.labBook`), rebuilt from the classic `LabBookView`: markers grouped by category,
/// each opening its history with a descriptive trend and "compare with a signal", manual entry, the
/// markers CSV / WHOOP biomarker import, delete, and the standing disclaimer. Reads and writes go through
/// the same store calls. The add-reading form is the classic `MarkerEditorView` under the Broop skin.
struct BroopHealthLabBookView: View {
    @EnvironmentObject private var repo: Repository

    @State private var markers: [LabMarkerRow] = []
    @State private var loaded = false
    @State private var showEditor = false
    @State private var showAbout = false
    @State private var importing = false
    @State private var importSummary: String?
    @State private var importFailed = false

    private static let categoryOrder: [LabMarkerCategory] = [
        .bloodPanel, .bloodPressure, .bodyMeasurement, .imaging, .appointmentNote, .other,
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 10)
                HStack(spacing: 10) {
                    BroopHealthButton(title: String(localized: "Add a reading"), symbol: "plus") { showEditor = true }
                    BroopHealthButton(title: importing ? String(localized: "Importing…") : String(localized: "Import CSV"),
                                      symbol: "tray.and.arrow.down", kind: .secondary) { pickCsv() }
                        .disabled(importing)
                }
                .padding(.top, 18)
                if let importSummary {
                    Text(verbatim: importSummary)
                        .font(BroopType.medium(14))
                        .foregroundStyle(importFailed ? BroopHealthPalette.amber : BroopHealthPalette.mint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                BroopHealthFootnote(text: String(localized: "Import a markers CSV (date, marker, value, unit) or a WHOOP biomarker export. Names that match the catalog fold onto your markers; anything else comes in as a custom marker. Rows that can't be read are skipped and counted, never guessed."))
                    .padding(.top, 10)

                if !loaded {
                    ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 40)
                } else if markers.isEmpty {
                    BroopHealthEmpty(symbol: "square.and.pencil", title: String(localized: "Keep your own numbers here"),
                                     message: String(localized: "Type in a blood-pressure reading or a cholesterol value from your last appointment. It stays on \(Platform.deviceNounPhrase), and over time you'll see how it lines up with your sleep, heart rate and recovery."))
                        .padding(.top, 20)
                } else {
                    ForEach(categories, id: \.self) { cat in section(cat).padding(.top, BroopMetrics.section) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    BroopHealthFootnote(text: String(localized: "Lab Book is a private notebook, not a medical service. NOOP stores and lines up the numbers you enter. It doesn't test, read, diagnose, or advise. Your records never leave \(Platform.deviceNounPhrase); there's no account or cloud, so it isn't \"HIPAA-covered.\" Always rely on your doctor or pharmacist to interpret results."))
                    Button { showAbout = true } label: {
                        BroopCaps(String(localized: "Read the full note →"), size: 10.5, color: BroopHealthPalette.chartBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Lab Book")) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "What Lab Book is (and isn't)")) { showAbout = true }
            }
        }
        .broopHealthScreen()
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showEditor) {
            MarkerEditorView { drafts in await save(drafts) }
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAbout) { BroopHealthLabAboutSheet() }
    }

    // MARK: Header

    private var header: some View {
        let keys = Set(markers.map(\.markerKey)).count
        return HStack(spacing: 0) {
            stat("\(keys)", keys == 1 ? String(localized: "Marker") : String(localized: "Markers"))
            Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
            stat("\(markers.count)", markers.count == 1 ? String(localized: "Reading") : String(localized: "Readings"))
            Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
            stat(markers.last.map { BroopHealthFormat.shortDay($0.day) } ?? "–", String(localized: "Latest"))
        }
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value).font(BroopType.number(24)).foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            BroopCaps(label, size: 10, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Sections

    private var categories: [LabMarkerCategory] {
        let present = Set(markers.compactMap { LabMarkerCategory(rawValue: $0.category) })
        return Self.categoryOrder.filter { present.contains($0) }
    }

    private func section(_ cat: LabMarkerCategory) -> some View {
        let keys = Set(markers.filter { $0.category == cat.rawValue }.map(\.markerKey))
            .sorted { Self.name($0) < Self.name($1) }
        return VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: cat.displayName,
                               trailing: keys.count == 1 ? String(localized: "1 marker") : String(localized: "\(keys.count) markers"))
            VStack(spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    let rows = markers.filter { $0.markerKey == key }
                    NavigationLink {
                        BroopHealthMarkerDetail(markerKey: key, readings: rows) { id in await delete(id) }
                    } label: { markerRow(key, rows) }
                    .buttonStyle(BroopPressableStyle())
                }
            }
        }
    }

    private func markerRow(_ key: String, _ rows: [LabMarkerRow]) -> some View {
        let latest = rows.last
        let nums = rows.compactMap(\.value)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                BroopCaps(Self.name(key), size: 11.5).lineLimit(1)
                Text(verbatim: latest.map { String(localized: "last taken \(LabBookFormat.dayFromKey($0.day))") }
                     ?? String(localized: "no readings yet"))
                    .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer(minLength: 8)
            if nums.count > 1 {
                BroopHealthSparkline(values: nums).frame(width: 56, height: 22)
            }
            Text(verbatim: Self.valueLabel(latest, key: key))
                .font(BroopType.number(18)).foregroundStyle(BroopPalette.textPrimary).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(BroopPalette.textSecondary)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        .accessibilityElement(children: .combine)
    }

    static func name(_ key: String) -> String {
        MarkerCatalog.definition(for: key)?.displayName ?? LabBookView.humanise(key)
    }

    static func valueLabel(_ row: LabMarkerRow?, key: String) -> String {
        guard let row else { return "–" }
        if let v = row.value { return "\(LabBookFormat.value(v, key: key)) \(row.unit)" }
        return row.valueText ?? "–"
    }

    // MARK: Store

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        var all: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            all += (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
        }
        markers = all.sorted { $0.takenAt < $1.takenAt }
        loaded = true
    }

    private func save(_ drafts: [LabMarkerRow]) async {
        guard !drafts.isEmpty, let store = await repo.storeHandle() else { return }
        try? await store.upsertLabMarkers(drafts)
        await repo.refresh()
        await load()
    }

    private func delete(_ id: String) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLabMarker(id: id)
        await repo.refresh()
        await load()
    }

    // MARK: CSV import (classic importMarkersCsv)

    private func pickCsv() {
        Task {
            guard let url = await DocumentPicker.importFile([.commaSeparatedText, .plainText]) else { return }
            await importCsv(url)
        }
    }

    private func importCsv(_ url: URL) async {
        importing = true; importSummary = nil; importFailed = false
        defer { importing = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let isWhoop = WhoopBiomarkerExportParser.matches(data: data)
            let result = isWhoop ? WhoopBiomarkerExportParser.parse(data: data) : LabMarkerCsvImport.parse(data: data)
            let sourceId = isWhoop ? WhoopBiomarkerExportParser.sourceId : LabMarkerCsvImport.sourceId
            guard !result.fileTooLarge else {
                importSummary = String(localized: "That file is too large for a markers CSV import."); importFailed = true; return
            }
            guard result.importedReadings > 0 else {
                importSummary = String(localized: "No usable rows found. Check the file has date, marker and value columns.")
                importFailed = true
                log("Lab Book CSV: no usable rows (\(result.skippedRows) skipped)")
                return
            }
            guard let store = await repo.storeHandle() else {
                importSummary = String(localized: "Couldn't open the local store."); importFailed = true; return
            }
            let rows = result.rows.map { r -> LabMarkerRow in
                let epoch = LabBookFormat.noonEpoch(r.day)
                return LabMarkerRow(id: "\(r.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))", deviceId: repo.deviceId,
                                    markerKey: r.markerKey, category: r.category.rawValue, day: r.day, takenAt: epoch,
                                    value: r.value, valueText: nil, unit: r.unit, source: sourceId, note: r.note,
                                    referenceText: nil)
            }
            try await store.upsertLabMarkers(rows)
            await repo.refresh()
            await load()
            var msg = String(localized: "Imported \(result.importedReadings) readings (\(result.distinctMarkers) markers)")
            if let a = result.earliestDay, let b = result.latestDay, a != b { msg += " · \(a)-\(b)" }
            if result.skippedRows > 0 {
                msg += " · " + (result.skippedRows == 1 ? String(localized: "1 row skipped")
                                : String(localized: "\(result.skippedRows) rows skipped"))
            }
            if result.notMeasured > 0 {
                msg += " · " + (result.notMeasured == 1 ? String(localized: "1 not measured")
                                : String(localized: "\(result.notMeasured) not measured"))
            }
            importSummary = msg
            log("Lab Book CSV: \(result.importedReadings) readings, \(result.distinctMarkers) markers, \(result.skippedRows) rejected")
        } catch {
            importSummary = String(localized: "Import failed: \(error.localizedDescription)")
            importFailed = true
            log("Lab Book CSV failed: \(error.localizedDescription)")
        }
    }

    /// Counts only into the strap log, never a file name or a value (#421).
    private func log(_ line: String) {
        // Through the app model rather than an observed LiveState: logging must not subscribe this whole
        // screen to the live stream.
        AppModel.shared?.live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] Import \(line)")
    }
}

/// A plain polyline scaled to its own range.
struct BroopHealthSparkline: View {
    let values: [Double]
    var color: Color = BroopHealthPalette.chartBlue

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = hi - lo
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                 y: size.height * CGFloat(1 - (span > 0 ? (v - lo) / span : 0.5)))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Marker detail

/// One marker: its readings as a Trend View style chart, the descriptive trend sentence, the reference
/// text from the user's own report, "compare with a signal" (the classic windowed-aggregate Pearson and
/// restrained copy), and the full history with delete.
struct BroopHealthMarkerDetail: View {
    let markerKey: String
    let readings: [LabMarkerRow]
    let onDelete: (String) async -> Void

    @EnvironmentObject private var repo: Repository
    @State private var rows: [LabMarkerRow] = []
    @State private var signal: MetricDescriptor?
    @State private var window: LabWindow = .fortnight
    @State private var pairs: [WindowedPair] = []
    @State private var correlation: Correlation?
    @State private var computing = false
    @State private var selection: BroopHealthPoint?
    @State private var pendingDelete: LabMarkerRow?

    private var name: String { BroopHealthLabBookView.name(markerKey) }
    private var unit: String { rows.last?.unit ?? MarkerCatalog.definition(for: markerKey)?.canonicalUnit ?? "" }
    private var numeric: [LabMarkerRow] { rows.filter { $0.value != nil } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary.padding(.top, 14)
                if numeric.count > 1 { chart.padding(.top, 20) }
                Text(verbatim: trendSentence)
                    .font(BroopType.medium(16)).foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                if let ref = rows.last(where: { $0.referenceText?.isEmpty == false })?.referenceText {
                    HStack(spacing: 8) {
                        BroopCaps(String(localized: "From your report"), size: 9.5, color: BroopPalette.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(BroopHealthPalette.chipNeutralFill))
                        Text(verbatim: ref).font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textBody)
                    }
                    .padding(.top, 10)
                }
                if !numeric.isEmpty { compare.padding(.top, BroopMetrics.section) }
                history.padding(.top, BroopMetrics.section)
                BroopHealthFootnote(text: String(localized: "These are your own numbers shown back to you. NOOP doesn't decide whether any value is normal, high or low."))
                    .padding(.top, 18)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: name, subtitle: rows.count == 1 ? String(localized: "1 reading")
                              : String(localized: "\(rows.count) readings"))
        }
        .broopHealthScreen()
        .onAppear { if rows.isEmpty { rows = readings } }
        .task(id: "\(signal?.id ?? "")|\(window.rawValue)|\(repo.refreshSeq)") { await recompute() }
        .confirmationDialog(Text("Delete this reading?"), isPresented: Binding(get: { pendingDelete != nil },
                                                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let row = pendingDelete {
                    rows.removeAll { $0.id == row.id }
                    Task { await onDelete(row.id) }
                }
                pendingDelete = nil
            }
        }
    }

    private var summary: some View {
        let latest = rows.last
        return VStack(alignment: .leading, spacing: 6) {
            BroopCaps(selection.map { BroopHealthFormat.weekday($0.day) } ?? String(localized: "Latest"),
                      size: 12, color: BroopPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: selection.map { LabBookFormat.value($0.value, key: markerKey) }
                     ?? latest.map { r in r.value.map { LabBookFormat.value($0, key: markerKey) } ?? (r.valueText ?? "–") } ?? "–")
                    .font(BroopType.number(40)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(40)
                Text(verbatim: unit).font(BroopType.medium(16)).foregroundStyle(BroopPalette.textPrimary)
            }
            if let latest, selection == nil {
                Text(verbatim: LabBookFormat.dayFromKey(latest.day)).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
    }

    private var chart: some View {
        let pts = numeric.compactMap { r -> BroopHealthPoint? in
            guard let v = r.value, let d = BroopHealthFormat.date(r.day) else { return nil }
            return BroopHealthPoint(day: r.day, date: d, value: v, segment: "a")
        }
        let lo = pts.map(\.value).min() ?? 0, hi = pts.map(\.value).max() ?? 1
        let pad = max((hi - lo) * 0.2, abs(hi) * 0.03, 0.1)
        return BroopHealthTrendChart(points: pts, style: .line, yDomain: (lo - pad)...(hi + pad),
                                     valueLabel: { LabBookFormat.value($0, key: markerKey) },
                                     axisLabel: { LabBookFormat.plain($0) }, labelsPoints: pts.count <= 8,
                                     selection: $selection, height: 220)
    }

    private var trendSentence: String {
        guard let last = numeric.last?.value else {
            return rows.last?.valueText.map { String(localized: "Latest entry: \($0).") } ?? String(localized: "No numeric readings yet.")
        }
        guard numeric.count >= 2 else {
            return String(localized: "One reading so far: \(LabBookFormat.value(last, key: markerKey)) \(unit). Log a few more to see a trend.")
        }
        let shown = numeric.suffix(3).compactMap(\.value)
        let arrowed = shown.map { LabBookFormat.value($0, key: markerKey) }.joined(separator: " → ")
        let first = shown.first ?? last
        if last > first { return String(localized: "Your last \(shown.count) readings: \(arrowed) \(unit), trending up.") }
        if last < first { return String(localized: "Your last \(shown.count) readings: \(arrowed) \(unit), trending down.") }
        return String(localized: "Your last \(shown.count) readings: \(arrowed) \(unit), holding steady.")
    }

    // MARK: Compare with a signal

    private var compare: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "Compare with a signal"))
            Text("NOOP averages the signal over the \(window.phrase) before each reading and lines the two up.")
                .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(LabBookSignals.options) { m in
                    Button { signal = m } label: {
                        Label(m.title, systemImage: signal?.id == m.id ? "checkmark" : m.icon)
                    }
                }
                if signal != nil {
                    Divider()
                    Button(role: .destructive) { signal = nil } label: { Label("Clear", systemImage: "xmark") }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: signal?.icon ?? "plus.circle").font(.system(size: 18, weight: .light))
                        .foregroundStyle(BroopPalette.textSecondary)
                    BroopCaps(signal?.title ?? String(localized: "Choose a signal"), size: 12)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(BroopPalette.textPrimary)
                }
                .padding(.horizontal, 18).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopHealthPalette.dropdown))
            }
            BroopHealthSegmented(options: LabWindow.allCases, selection: $window) { $0.label }
            result
        }
    }

    @ViewBuilder private var result: some View {
        let n = pairs.count
        Group {
            if signal == nil {
                Text("Pick a wearable signal (resting HR, HRV, sleep, Charge, weight…) to line it up against this marker.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            } else if computing {
                Text("Lining them up…").font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            } else if n < LabBookSignals.floor {
                Text(n == 0
                     ? "No overlap yet between this marker and \(signal?.title.lowercased() ?? String(localized: "that signal")). Log a few more readings (and keep wearing your strap)."
                     : (n == 1
                        ? "1 reading lines up so far, not enough to read a trend yet (NOOP waits for \(LabBookSignals.floor))."
                        : "\(n) readings line up so far, not enough to read a trend yet (NOOP waits for \(LabBookSignals.floor))."))
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            } else if let c = correlation {
                let color = c.r >= 0 ? BroopHealthPalette.chipGoodText : BroopHealthPalette.chipBadText
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        BroopCaps("\(name) ↔ \(signal?.title ?? "")", size: 11).lineLimit(2)
                        Spacer()
                        Text(verbatim: "r = \(LabBookSignals.signedR(c.r))").font(BroopType.number(18)).foregroundStyle(color)
                    }
                    Text(verbatim: LabBookSignals.insightSentence(markerName: name, signalName: signal?.title ?? "the signal", r: c.r))
                        .font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BroopPalette.track)
                            Capsule().fill(color).frame(width: g.size.width * CGFloat(min(abs(c.r), 1)))
                        }
                    }
                    .frame(height: 5)
                    Text("\(n) readings used · \(LabBookSignals.strengthWord(c.r)) \(LabBookSignals.directionWord(c.r)) association. This is your own data sitting side by side. It's not a medical finding, and it shows association, not cause.")
                        .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("\(n) readings line up, but there isn't enough variation to compute a relationship.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func recompute() async {
        guard let signal else { pairs = []; correlation = nil; return }
        computing = true
        defer { computing = false }
        let markerSeries = await repo.series(key: markerKey, source: WhoopStore.labBookSourceId)
        let wearable = await repo.exploreSeries(key: signal.key, source: signal.source)
        let built = LabBookProjection.pairMarkerToWearable(marker: markerSeries, wearable: wearable, windowDays: window.days)
        pairs = built
        correlation = built.count >= LabBookSignals.floor
            ? CorrelationEngine.pearson(LabBookProjection.correlationInput(built)) : nil
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopHealthHeading(text: String(localized: "History"))
            VStack(spacing: 0) {
                let list = Array(rows.reversed())
                ForEach(Array(list.enumerated()), id: \.element.id) { i, row in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: BroopHealthLabBookView.valueLabel(row, key: markerKey))
                                .font(BroopType.number(17)).foregroundStyle(BroopPalette.textPrimary)
                            Text(verbatim: LabBookFormat.dayFromKey(row.day))
                                .font(BroopType.regular(12.5)).foregroundStyle(BroopPalette.textSecondary)
                            if let note = row.note, !note.isEmpty {
                                Text(verbatim: note).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textBody)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { pendingDelete = row } label: {
                            Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(BroopPalette.textSecondary)
                                .frame(width: 34, height: 34).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Delete this reading"))
                    }
                    .padding(.vertical, 11)
                    if i < list.count - 1 { BroopHairline() }
                }
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        }
    }
}

/// The full "About Lab Book" note (classic first-use disclaimer).
private struct BroopHealthLabAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BroopCaps(String(localized: "About Lab Book"), size: 13).frame(maxWidth: .infinity).padding(.top, 22)
                Text("A private notebook, not a medical service.").font(BroopType.demi(20)).foregroundStyle(BroopPalette.textPrimary)
                ForEach(points, id: \.self) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(BroopHealthPalette.chartBlue).frame(width: 6, height: 6).padding(.top, 7)
                        Text(verbatim: p).font(BroopType.regular(15)).foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                BroopHealthButton(title: String(localized: "Got it")) { dismiss() }.padding(.top, 6)
            }
            .padding(BroopMetrics.page)
        }
        .background(BroopPalette.bgMid.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private var points: [String] {
        [
            String(localized: "NOOP stores and lines up the numbers you enter yourself. It does not test you, read your results, give medical advice, or diagnose anything."),
            String(localized: "Anything you see here (including any side-by-side trend) is your own information shown back to you. It's an association, never a cause, and never a medical finding."),
            String(localized: "NOOP never decides whether a value is \"normal,\" \"high,\" or \"low.\" Any reference range shown is exactly what you typed from your own report."),
            String(localized: "Your records never leave \(Platform.deviceNounPhrase). There's no account, no cloud, no NOOP server. Because NOOP is an independent app you run yourself (not a healthcare provider), it isn't \"HIPAA-covered,\" and that protection doesn't apply here; the safety comes from the data being local-only and yours."),
            String(localized: "Always rely on your doctor, pharmacist, or a qualified professional to interpret results and make decisions. If a number worries you, talk to them, not to an app."),
        ]
    }
}
#endif
