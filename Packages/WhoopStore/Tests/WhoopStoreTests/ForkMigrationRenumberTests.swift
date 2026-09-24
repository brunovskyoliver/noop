import XCTest
import GRDB
@testable import WhoopStore

/// A fork build shipped its checkpoint and workout-suggestion migrations as v45/v46/v47 before upstream
/// claimed those numbers. They now run as v47/v48/v49, after upstream's chain. A database that already
/// applied the old identifiers must migrate forward without failing on the tables and columns it has.
final class ForkMigrationRenumberTests: XCTestCase {

    private static let renamed = [
        "v47-analysis-checkpoints": "v45-analysis-checkpoints",
        "v48-checkpoint-device-scope": "v46-checkpoint-device-scope",
        "v49-workout-suggested-class": "v47-workout-suggested-class",
    ]

    func testDatabaseMigratedUnderOldForkIdentifiersConverges() throws {
        let db = try DatabaseQueue()
        try WhoopStore.makeMigrator().migrate(db)
        // Stand in for the fork build: its schema is present, recorded under the old names, and
        // upstream's v45/v46 have not run yet.
        try db.write { db in
            for (new, old) in Self.renamed {
                try db.execute(sql: "UPDATE grdb_migrations SET identifier = ? WHERE identifier = ?",
                               arguments: [old, new])
            }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier IN ('v45-rr-source-index', 'v46-lift-log')")
            try db.execute(sql: "DROP INDEX rrInterval_source_suspect")
        }

        XCTAssertNoThrow(try WhoopStore.makeMigrator().migrate(db))

        try db.read { db in
            let applied = try String.fetchSet(db, sql: "SELECT identifier FROM grdb_migrations")
            for new in Self.renamed.keys { XCTAssertTrue(applied.contains(new), new) }
            XCTAssertTrue(applied.contains("v46-lift-log"))
            let columns = try db.columns(in: "workout").map(\.name)
            XCTAssertEqual(columns.filter { $0 == "suggestedClass" }.count, 1)
            XCTAssertTrue(try db.tableExists("analysisCheckpoint"))
            XCTAssertTrue(try db.tableExists("liftSet"))
            XCTAssertTrue(try db.indexes(on: "rrInterval").contains { $0.name == "rrInterval_source_suspect" })
        }
    }
}
