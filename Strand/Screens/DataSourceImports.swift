import SwiftUI
import UniformTypeIdentifiers
import StrandImport
import StrandAnalytics
import WhoopStore
import WhoopProtocol   // #137: Streams / HRSample, to persist an imported activity's per-sample HR

/// The lightweight file imports behind Data Sources (nutrition CSV, lifting log, workout file, wearable
/// export) and the Apple Health purge, lifted out of `DataSourcesView` so the classic screen and the
/// Broop Data Sources screen run ONE implementation. Each call parses, writes and refreshes exactly as
/// the classic screen always did, and returns the summary line the screen shows.
@MainActor
enum DataSourceImports {
    struct Outcome {
        let summary: String
        let failed: Bool
    }

    enum Target {
        case whoop
        case appleHealth
        case xiaomi
        case nutrition
        case lifting
        case activityFile
        case wearable

        var allowedContentTypes: [UTType] {
            // `.folder` lets macOS users point at an *unzipped* export directory. On iOS the Files
            // picker can't meaningfully pick a folder here, and including `UTType.folder` in the type
            // list greys out the .zip itself — so the picker opens but nothing is selectable
            // (issue #179). iOS therefore offers only the concrete file types.
            switch self {
            case .whoop:
                #if os(macOS)
                return [.zip, .folder]
                #else
                return [.zip]
                #endif
            case .appleHealth:
                #if os(macOS)
                return [.zip, .xml, .folder]
                #else
                return [.zip, .xml]
                #endif
            case .xiaomi:
                // The Mi Fitness sandbox is shared as a .zip (or, on macOS, an unzipped
                // folder); the bare `<user_id>.db` is also accepted directly.
                let db = UTType(filenameExtension: "db") ?? .data
                #if os(macOS)
                return [.zip, .folder, db]
                #else
                return [.zip, db]
                #endif
            case .nutrition:
                return [.commaSeparatedText, .plainText]
            case .lifting:
                // Hevy exports .csv, Liftosaur exports .json — accept both (plus plain text, since some
                // share sheets type a .csv as text/plain). The importer sniffs the actual format.
                return [.commaSeparatedText, .json, .plainText]
            case .activityFile:
                // GPX/TCX are XML; FIT is binary. None have a system UTType, so build them by extension
                // (falling back to .xml/.data) and add .data so an untyped share-sheet file is selectable.
                // The importer routes by extension/magic-bytes regardless.
                let gpx = UTType(filenameExtension: "gpx") ?? .xml
                let tcx = UTType(filenameExtension: "tcx") ?? .xml
                let fit = UTType(filenameExtension: "fit") ?? .data
                return [gpx, tcx, fit, .xml, .data]
            case .wearable:
                // Oura is a single .json; Fitbit (Google Takeout) and Garmin (GDPR) are .zip bundles.
                // On macOS an unzipped folder is also accepted. The importer sniffs the brand by content.
                #if os(macOS)
                return [.json, .zip, .folder, .data]
                #else
                return [.json, .zip, .data]
                #endif
            }
        }
    }

    /// Write one privacy-safe line into the SAME exported strap log the WHOOP path uses, so a tester's
    /// file import is no longer invisible in a shared debug bundle (issue #421 parity). Brand label +
    /// COUNTS only, never a file name, a path, or any health value. Prefixed "Import " so it's
    /// distinguishable from the WHOOP / HR-strap / HR-out lines. Timestamp matches the rest of the log.
    /// The Android twin logs the same shape from DataSourcesScreen.runImport via ble.externalLog.
    static func logImport(_ line: String, live: LiveState) {
        live.append(log: "[\(AppModel.logTimeFormatter.string(from: Date()))] Import \(line)")
    }

    /// Parse a daily-nutrition CSV and upsert it into the metric-series store under the
    /// dedicated "nutrition-csv" source, then refresh so Explore/Insights see the new keys.
    static func importNutrition(url: URL, repo: Repository, live: LiveState) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = NutritionCsvImporter.parse(data: data)
            guard result.importedDays > 0 else {
                logImport("Nutrition CSV: no usable rows (\(result.skippedRows) skipped)", live: live)
                return Outcome(summary: String(localized: "No usable rows found. Check the file has a date column (yyyy-MM-dd) and daily totals."),
                               failed: true)
            }
            guard let store = await repo.storeHandle() else {
                return Outcome(summary: String(localized: "Couldn't open the local store."), failed: true)
            }
            let points = result.metricPoints.map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }
            try await store.upsertMetricSeries(points, deviceId: NutritionCsvImporter.sourceId)
            await repo.refresh()
            var msg = String(localized: "Imported \(result.importedDays) days (\(points.count) values)")
            if let a = result.earliestDay, let b = result.latestDay, a != b { msg += " · \(a)-\(b)" }
            if result.skippedRows > 0 {
                // Whole-phrase variants per count; the separator stays outside the localized key.
                msg += " · " + (result.skippedRows == 1
                                ? String(localized: "1 row skipped")
                                : String(localized: "\(result.skippedRows) rows skipped"))
            }
            logImport("Nutrition CSV: \(result.importedDays) days, \(points.count) values, \(result.skippedRows) rejected", live: live)
            return Outcome(summary: msg, failed: false)
        } catch {
            logImport("Nutrition CSV failed: \(error.localizedDescription)", live: live)
            return Outcome(summary: String(localized: "Import failed: \(error.localizedDescription)"), failed: true)
        }
    }

    /// Parse a Hevy CSV / Liftosaur JSON lifting export and upsert each workout as a Strength session
    /// (source "lifting") with a transparent volume-load note. No `strain` is stored, so these never
    /// feed the HR-based Effort — lifting volume is reported alongside it, never folded into it.
    static func importLifting(url: URL, repo: Repository, live: LiveState) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let result = LiftingImporter.parse(data: data)
            guard result.sessionCount > 0 else {
                logImport("Lifting log: no workouts found (\(result.skipped) skipped)", live: live)
                return Outcome(summary: String(localized: "No workouts found. Point at a Hevy CSV export or a Liftosaur JSON export."),
                               failed: true)
            }
            guard let store = await repo.storeHandle() else {
                return Outcome(summary: String(localized: "Couldn't open the local store."), failed: true)
            }
            let rows = result.sessions.map { s in
                WorkoutRow(
                    startTs: Int(s.start.timeIntervalSince1970),
                    endTs: Int(s.end.timeIntervalSince1970),
                    sport: LiftingImporter.sport,
                    source: LiftingImporter.sourceId,
                    durationS: s.durationS,
                    energyKcal: nil,
                    avgHr: nil,
                    maxHr: nil,
                    strain: nil,                 // never a fabricated cardiovascular strain
                    distanceM: nil,
                    zonesJSON: nil,
                    notes: s.volumeLoadNote(), steps: nil,
                    suggestedClass: nil, suggestedClassConfidence: nil
                )
            }
            try await store.upsertWorkouts(rows, deviceId: LiftingImporter.sourceId)
            await repo.refresh()
            let totalVolume = result.sessions.reduce(0.0) { $0 + $1.volumeLoadKg }
            // Whole-phrase variants per count so translators never see a stitched plural.
            var msg = result.sessionCount == 1
                ? String(localized: "Imported 1 workout")
                : String(localized: "Imported \(result.sessionCount) workouts")
            if totalVolume > 0 {
                msg += " · " + String(localized: "\(LiftingImporter.groupedKg(totalVolume)) kg total volume")
            }
            if let a = result.earliest, let b = result.latest {
                let span = liftingDayFormatter
                let lo = span.string(from: a), hi = span.string(from: b)
                if lo != hi { msg += " · \(lo)-\(hi)" }
            }
            if result.skipped > 0 { msg += " · " + String(localized: "\(result.skipped) skipped") }
            logImport("Lifting log: \(result.sessionCount) workouts, \(result.skipped) rejected", live: live)
            return Outcome(summary: msg, failed: false)
        } catch {
            logImport("Lifting log failed: \(error.localizedDescription)", live: live)
            return Outcome(summary: String(localized: "Import failed: \(error.localizedDescription)"), failed: true)
        }
    }

    /// Parse a single GPX / TCX / FIT activity file and upsert it as one workout (source
    /// "activity-file"). The route polyline isn't persisted on macOS (the shared WorkoutRow has no route
    /// column), but distance / HR / energy / ascent and an honest "N GPS points · M HR samples" note are.
    ///
    /// #137: the imported ride's REAL per-sample HR is now ALSO persisted as an HR stream under the
    /// `activity-file` deviceId, and `activity-file` is registered as an `.activityFile` device. Together
    /// (A + B1) that lets a strap-less day's ride light the day Effort ring: the per-day owner resolver
    /// (`IntelligenceEngine.resolveDayOwner`) treats `activity-file` as the LOWEST-ranked candidate
    /// (priority 3, below whole-day imports at 2) and — being the only source with HR that day — picks it
    /// as the day owner, so `dayHr` reads the ride's HR and Effort scores from it. On a day the user ALSO
    /// wore the strap, the strap (priority 0/1) wins ownership and the imported HR is ignored for Effort;
    /// on a day a whole-day WHOOP import (priority 2) has HR, that import wins over the ride too. The
    /// workout row itself still stores `strain = nil` (we never fabricate a per-workout strain); the day
    /// Effort is computed from the measured HR stream, exactly as it is for a worn strap.
    static func importActivityFile(url: URL, model: AppModel, repo: Repository, live: LiveState) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            // Cap the read so a hostile huge file can't OOM us before the parser's own guards.
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if data.count > ActivityFileImporter.maxBytes {
                logImport("Workout file failed: file too large", live: live)
                return Outcome(summary: String(localized: "That file is too large to import."), failed: true)
            }
            let result = ActivityFileImporter.parse(data: data, filename: url.lastPathComponent)
            guard let activity = result.activity, let s = activity.durationS, s > 0 else {
                logImport("Workout file: no usable activity found", live: live)
                return Outcome(summary: String(localized: "No usable activity found. Point at a .gpx, .tcx or .fit workout file."),
                               failed: true)
            }
            guard let store = await repo.storeHandle() else {
                return Outcome(summary: String(localized: "Couldn't open the local store."), failed: true)
            }
            let sport = ActivityFileImporter.workoutSport(from: activity.sport)
            let row = WorkoutRow(
                startTs: Int(activity.start.timeIntervalSince1970),
                endTs: Int(activity.end.timeIntervalSince1970),
                sport: sport,
                source: ActivityFileImporter.sourceId,
                durationS: activity.durationS,
                energyKcal: activity.energyKcal,
                avgHr: activity.avgHr,
                maxHr: activity.maxHr,
                strain: nil,                         // never a fabricated cardiovascular strain
                distanceM: activity.distanceM,
                zonesJSON: nil,
                notes: activity.importNote(),
                steps: activity.steps,                // #1058: per-session steps, summed into the day below
                suggestedClass: nil, suggestedClassConfidence: nil
            )
            try await store.upsertWorkouts([row], deviceId: ActivityFileImporter.sourceId)

            // #137 (A): persist the ride's real per-sample HR under the activity-file source. The
            // insert is keyed on (deviceId, ts), so re-importing the same file is idempotent (an
            // identical ts overwrites, never duplicates). Skipped when the file carried no
            // timestamped HR (a pure GPS track) — nothing to store, so day Effort stays honestly dark.
            if !activity.hrSamples.isEmpty {
                let hr = activity.hrSamples.map { HRSample(ts: $0.ts, bpm: $0.bpm) }
                _ = try? await store.insert(Streams(hr: hr), deviceId: ActivityFileImporter.sourceId)
            }
            // #1058: recompute the day's activity-file step total as the SUM over ALL that day's
            // sessions (now that each carries its own steps), so a second file for the same day ADDS
            // to the first instead of clobbering it. Idempotent on re-import: the file's workout row
            // (keyed on startTs+sport) is replaced, not duplicated, so the re-summed total is unchanged.
            // Only recompute when THIS file contributed steps (a foot sport); a cycling import leaves
            // the day's step total untouched.
            if (activity.steps ?? 0) > 0 {
                let dayStart = Calendar.current.startOfDay(for: activity.start)
                let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
                    ?? dayStart.addingTimeInterval(86_400)
                let daySteps = (try? await store.sumWorkoutSteps(
                    deviceId: ActivityFileImporter.sourceId,
                    from: Int(dayStart.timeIntervalSince1970),
                    to: Int(dayEnd.timeIntervalSince1970))) ?? 0
                if daySteps > 0 {
                    let metric = DailyMetric(
                        day: Repository.localDayKey(activity.start),
                        totalSleepMin: nil,
                        efficiency: nil,
                        deepMin: nil,
                        remMin: nil,
                        lightMin: nil,
                        disturbances: nil,
                        restingHr: nil,
                        avgHrv: nil,
                        recovery: nil,
                        strain: nil,
                        exerciseCount: nil,
                        steps: daySteps
                    )
                    try? await store.upsertDailyMetrics([metric], deviceId: ActivityFileImporter.sourceId)
                }
            }

            // #137 (B1): register `activity-file` as an `.activityFile` device so the per-day owner
            // resolver can pick it as the day owner on a strap-less day (it iterates the registry's
            // paired devices; an unregistered source is invisible to it). The distinct kind ranks it
            // at priority 3 — below whole-day imports (2) — so a full-day WHOOP import always wins a
            // day it has HR for. status `.paired`, NEVER `.active`, so it can never displace the live
            // strap as the active device; capability `.hr` marks what the source CAN provide (presence
            // per-day is still gated by an actual HR read in the resolver). Idempotent, makeActive: false.
            model.registerDevice(
                PairedDevice(
                    id: ActivityFileImporter.sourceId,
                    brand: "Workout files",
                    model: "",
                    sourceKind: .activityFile,
                    capabilities: [.hr],
                    status: .paired,
                    addedAt: Int(Date().timeIntervalSince1970),
                    lastSeenAt: Int(Date().timeIntervalSince1970)
                ),
                makeActive: false
            )

            await repo.refresh()
            logImport("Workout file (\(sport)): 1 workout imported", live: live)
            return Outcome(summary: ActivityFileImporter.summaryText(activity), failed: false)
        } catch {
            logImport("Workout file failed: \(error.localizedDescription)", live: live)
            return Outcome(summary: String(localized: "Import failed: \(error.localizedDescription)"), failed: true)
        }
    }

    /// Parse a user's own Oura / Fitbit / Garmin data export and upsert it under the brand's own source
    /// (daily metrics + sleep sessions + reference-only metric series). The brand's own readiness/sleep
    /// score is NEVER mapped to a NOOP Charge/Effort/Rest — NOOP recomputes its own from the raw inputs.
    static func importWearable(url: URL, repo: Repository, live: LiveState) async -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let store = await repo.storeHandle() else {
                return Outcome(summary: String(localized: "Couldn't open the local store."), failed: true)
            }
            // Import & Data Ingest test mode: read the gate ONCE for this completion (the trace sink AND
            // the post-result file-meta line below share it), so a mid-import toggle can't make the two
            // reads disagree. The sink is nil when the mode is off (the importer then takes its
            // byte-identical untraced path). The importer runs nonisolated, so the sink hops each batch to
            // the main actor (LiveState is @MainActor) before appending, keeping the log race-free and
            // ordered. The brand is auto-detected, so the file-meta line is emitted AFTER the result lands.
            let importTracing = TestCentre.active(.dataImport)
            let result = try await WearableImporter.importExport(
                url: url, into: store,
                trace: importTracing
                    ? { @Sendable [weak live] lines in
                        Task { @MainActor [weak live] in
                            lines.forEach { live?.append(log: $0, domain: .dataImport) }
                        }
                      }
                    : nil)
            if importTracing {
                let ext = url.pathExtension
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                live.append(log: ImportTrace.fileMetaLine(sourceKind: result.brand.dataSourceKind,
                                                          ext: ext, sizeBytes: size),
                            domain: .dataImport)
            }
            await repo.refresh()
            logImport("\(result.brand.displayName) export: \(result.days.count) days, \(result.sleeps.count) sleeps, \(result.summary.skippedSpans) rejected", live: live)
            return Outcome(summary: WearableExportImporter.summaryText(result), failed: false)
        } catch {
            logImport("Wearable export failed: \(error.localizedDescription)", live: live)
            return Outcome(summary: String(localized: "Import failed: \(error.localizedDescription)"), failed: true)
        }
    }

    /// ah-delete (#616): purge every row stored under the "apple-health" source through the WhoopStore
    /// actor's `deleteAllData` (off the main executor, so a large dataset can't freeze the UI). The
    /// registry row is untouched — "apple-health" is a source, not a paired device. Returns the summary
    /// line, or nil when the store could not be opened.
    static func deleteAppleHealthData(model: AppModel, repo: Repository, live: LiveState) async -> String? {
        guard let store = await repo.storeHandle() else { return nil }
        do {
            try await store.deleteAllData(deviceId: model.appleDeviceId)
            await repo.refresh()
            // #833/v7.7.2: this purge clears the body-composition series (weight/body_fat/lean_mass/bmi/
            // vo2max) that live in metricSeries OUTSIDE refresh()'s diff, so refresh() may not bump
            // `refreshSeq` and AppleHealthView's re-mount cache would keep serving the now-DELETED data.
            // Explicitly drop the cache so the next visit re-reads the emptied source.
            repo.appleHealthCache = nil
            repo.appleHealthLoadedSeq = -1
            model.appleHealthImportSummary = nil
            model.appleHealthImportFailed = false
            logImport("Apple Health: imported data removed", live: live)
            return String(localized: "Removed all Apple Health imported data.")
        } catch {
            logImport("Apple Health delete failed: \(error.localizedDescription)", live: live)
            return String(localized: "Couldn't remove the data: \(error.localizedDescription)")
        }
    }

    private static var liftingDayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")   // sessions are stored at UTC; label the same span
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
