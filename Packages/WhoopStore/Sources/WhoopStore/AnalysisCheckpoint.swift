import Foundation
import GRDB

extension WhoopStore {
    public func analysisRevisionFingerprint() async throws -> String {
        try syncRead { db in
            let revision = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(revision), 0) FROM analysisRevision") ?? 0
            return "revision-v1:\(revision)"
        }
    }

    /// Revisions cover whole UTC days intersecting the read window, including old/new days of edits.
    public func analysisWindowRevision(deviceId: String, from: Int, to: Int) async throws -> String {
        try syncRead { db in
            let rows = try Row.fetchAll(db, sql: "SELECT day, revision FROM analysisRevision WHERE deviceId = ? AND day BETWEEN ? AND ? ORDER BY day",
                                       arguments: [deviceId, from / 86400, to / 86400])
            return rows.map { row in "\(row["day"] as Int):\(row["revision"] as Int)" }.joined(separator: ",")
        }
    }

    public func analysisCheckpoint(day: String, key: String) async throws -> Data? {
        try syncRead { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM analysisCheckpoint WHERE day = ? AND cacheKey = ?", arguments: [day, key])
        }
    }

    public func saveAnalysisCheckpoint(day: String, deviceId: String, key: String, payload: Data) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "INSERT INTO analysisCheckpoint(day, deviceId, cacheKey, payload) VALUES (?, ?, ?, ?) ON CONFLICT(day) DO UPDATE SET deviceId = excluded.deviceId, cacheKey = excluded.cacheKey, payload = excluded.payload", arguments: [day, deviceId, key, payload])
            // Recent history only; older historical rescoring can still use memory within its pass.
            try db.execute(sql: "DELETE FROM analysisCheckpoint WHERE day NOT IN (SELECT day FROM analysisCheckpoint ORDER BY day DESC LIMIT 64)")
        }
    }
}
