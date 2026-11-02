import Foundation
import GRDB

/// How much raw sensor data stays on the device, and the maintenance that enforces it.
///
/// The per-second streams cost about 38 MB a day stored as they were, 14 GB a year, while scores, sleep
/// sessions and metric series take almost nothing and are kept forever. So raw detail is rolling:
/// every stream keeps `fullDetailDays` days, and older days keep heart rate only, averaged per
/// `thinnedHRBucketSeconds`, which still draws an old day's chart for about 20 MB a year.
public enum RawRetention {
    /// The longest raw reader is the 21-night analysis window plus its 30 h lookback.
    public static let fullDetailDays = 30
    public static let thinnedHRBucketSeconds = 30
    /// Name of the `cursors` row holding the oldest unix second that still has full raw detail.
    public static let floorCursor = "rawFloorTs"

    /// How many days a pass ending at `todayStart` may rescore. A day below the floor has lost its raw
    /// data; rescoring it would delete or overwrite the good scores it already has, so no pass goes there.
    public static func scorableDayCount(maxDays: Int, todayStart: Int, lookbackSeconds: Int, floorTs: Int?) -> Int {
        guard let floorTs else { return maxDays }
        let available = (todayStart - lookbackSeconds - floorTs) / 86_400 + 1
        return max(1, min(maxDays, available))
    }
}

extension WhoopStore {
    /// Streams with a real per-row primary key: as rowid tables each one stores its key twice, table and
    /// index, which is half of the file. Listed explicitly so a new table opts in deliberately.
    static let compactedStreams = ["hrSample", "rrInterval", "gravitySample", "skinTempSample", "stepSample",
                                   "sleepStateSample", "respSample", "spo2Sample", "ppgHrSample",
                                   "ppgWaveformSample", "v18AuxSample"]
    /// Thinned rather than deleted. Every other stream, the capped ones included, is simply trimmed by age,
    /// so a device no longer in use does not keep its capped share forever.
    private static let thinnedStream = "hrSample"

    public func rawDataFloor() async throws -> Int? {
        try await cursor(RawRetention.floorCursor)
    }

    /// Whether any stream is still a rowid table, so the caller can wait for a charger before the rebuild.
    public func storageNeedsCompaction() async throws -> Bool {
        try syncRead { db in try Self.compactedStreams.contains { try Self.isRowidTable($0, db) } }
    }

    /// Advance the floor, trim everything older and, when `compact`, rebuild streams and shrink the file.
    /// Each table is one transaction, so a process kill costs only that table's progress and the next run
    /// resumes. Stops between tables when `shouldContinue` turns false. Writers queue behind a running step.
    public func runStorageMaintenance(now: Int, compact: Bool,
                                      shouldContinue: @Sendable () -> Bool = { true }) async throws {
        // The floor commits before any row goes, so a kill mid-way can never leave a day both rescorable
        // and stripped of its raw data.
        let cutoff = (now - RawRetention.fullDetailDays * 86_400) / 86_400 * 86_400
        let floor = max(cutoff, try await rawDataFloor() ?? cutoff)
        try await setCursor(RawRetention.floorCursor, floor)

        var rebuilt = false
        for table in Self.compactedStreams {
            guard shouldContinue() else { return }
            rebuilt = try syncWrite { db -> Bool in
                if compact, try Self.isRowidTable(table, db) {
                    try Self.rebuildWithoutRowid(table, floor: floor, db)
                    return true
                }
                try Self.trim(table, floor: floor, db)
                return false
            } || rebuilt
        }
        Self.removeStaleReplacedDatabases(nextTo: dbWriter.path, now: now)
        guard shouldContinue(), compact else { return }
        let reclaimable = try syncRead { db -> Int in
            let free = try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0
            let size = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 4096
            return free * size
        }
        // Freed pages are reused by new rows, so the daily trim never needs this; only a big one-off does.
        if rebuilt || reclaimable > 256 * 1024 * 1024 { try vacuumStore() }
    }

    /// A restore moves the previous database aside and nothing ever removed it. A month is enough to
    /// notice a bad restore.
    private static func removeStaleReplacedDatabases(nextTo path: String, now: Int) {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let cutoff = Date(timeIntervalSince1970: Double(now - RawRetention.fullDetailDays * 86_400))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("whoop-replaced-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func isRowidTable(_ table: String, _ db: Database) throws -> Bool {
        guard let sql = try String.fetchOne(
            db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", arguments: [table])
        else { return false }
        return !sql.uppercased().contains("WITHOUT ROWID")
    }

    /// Averages a thinned stream's rows into one row per bucket. Already-thinned buckets average to themselves.
    private static func thinnedHRSelect(floor: Int) -> String {
        let bucket = RawRetention.thinnedHRBucketSeconds
        return """
            SELECT deviceId, ts / \(bucket) * \(bucket) AS ts, CAST(ROUND(AVG(bpm)) AS INTEGER) AS bpm, MAX(synced) AS synced
            FROM hrSample WHERE ts < \(floor) GROUP BY deviceId, ts / \(bucket)
            """
    }

    private static func rebuildWithoutRowid(_ table: String, floor: Int, _ db: Database) throws {
        guard let createSQL = try String.fetchOne(
            db, sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", arguments: [table])
        else { return }
        // A dropped table takes its triggers and indexes with it, including the analysis-revision triggers
        // that cache invalidation depends on, so they are captured and recreated verbatim.
        let dependents = try String.fetchAll(db, sql: """
            SELECT sql FROM sqlite_master
            WHERE tbl_name = ? AND type IN ('index', 'trigger') AND sql IS NOT NULL
            """, arguments: [table])
        let temp = table + "__compact"
        guard let nameRange = createSQL.range(of: table) else { return }
        try db.execute(sql: createSQL.replacingCharacters(in: nameRange, with: temp) + " WITHOUT ROWID")
        if table == thinnedStream {
            try db.execute(sql: "INSERT INTO \(temp) (deviceId, ts, bpm, synced) \(thinnedHRSelect(floor: floor))")
        }
        let columns = try db.columns(in: table).map { "\"\($0.name)\"" }.joined(separator: ", ")
        // Sorted input makes the b-tree fill its pages in order rather than splitting them.
        let primaryKey = try db.primaryKey(table).columns.map { "\"\($0)\"" }.joined(separator: ", ")
        try db.execute(sql: """
            INSERT OR IGNORE INTO \(temp) (\(columns))
            SELECT \(columns) FROM \(table) WHERE ts >= \(floor) ORDER BY \(primaryKey)
            """)
        try db.execute(sql: "DROP TABLE \(table)")
        try db.execute(sql: "ALTER TABLE \(temp) RENAME TO \(table)")
        for sql in dependents { try db.execute(sql: sql) }
    }

    private static func trim(_ table: String, floor: Int, _ db: Database) throws {
        if table == thinnedStream {
            // Only the days the floor just passed still need thinning. A week's reach covers maintenance
            // that did not run for a while without rewriting the whole history every day.
            let from = floor - 7 * 86_400
            try db.execute(sql: """
                CREATE TEMP TABLE hrThin AS
                SELECT deviceId, ts / \(RawRetention.thinnedHRBucketSeconds) * \(RawRetention.thinnedHRBucketSeconds) AS ts,
                       CAST(ROUND(AVG(bpm)) AS INTEGER) AS bpm, MAX(synced) AS synced
                FROM hrSample WHERE ts >= \(from) AND ts < \(floor) GROUP BY deviceId, ts / \(RawRetention.thinnedHRBucketSeconds)
                """)
            try db.execute(sql: "DELETE FROM hrSample WHERE ts >= \(from) AND ts < \(floor)")
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm, synced) SELECT deviceId, ts, bpm, synced FROM hrThin")
            try db.execute(sql: "DROP TABLE hrThin")
        } else {
            try db.execute(sql: "DELETE FROM \(table) WHERE ts < \(floor)")
        }
    }

    /// The copy is written to disk: under the store's `temp_store = MEMORY` it would sit in RAM, and a
    /// multi-gigabyte copy gets the app killed. Non-async for GRDB's synchronous overload.
    private func vacuumStore() throws {
        try dbWriter.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA temp_store = FILE")
            defer { try? db.execute(sql: "PRAGMA temp_store = MEMORY") }
            try db.execute(sql: "VACUUM")
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
