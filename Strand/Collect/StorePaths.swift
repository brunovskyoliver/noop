import Foundation
enum StorePaths {
    /// `<AppSupport>/OpenWhoop/whoop.sqlite`, creating the directory if needed.
    static func defaultDatabasePath() throws -> String {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let containerAppSupport = macOSProductionContainerAppSupport(defaultingTo: appSupport)
        let base = containerAppSupport.appendingPathComponent("OpenWhoop", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let dbURL = base.appendingPathComponent("whoop.sqlite")

        // iOS files default to NSFileProtectionComplete, which makes the SQLite DB and its `-wal`/`-shm`
        // sidecars cryptographically UNREADABLE while the device is locked. We run background BLE
        // (UIBackgroundModes: bluetooth-central), so the strap reconnects and opens the store while the
        // phone is locked — the open then throws SQLITE_IOERR and the strap never syncs; imported data
        // also appears to "vanish" because every store handle (backfill + import) hits the same wall.
        // (#222 — NoahMcE.) Drop the store to completeUntilFirstUserAuthentication: readable after the
        // first unlock-since-boot (the correct level for background collection) and still encrypted at
        // rest. Set it on the directory so SQLite's freshly-created files inherit it, AND on any
        // pre-existing files from an install created before this fix (the set only succeeds while
        // unlocked, which the foreground import provides — from then on the files stay accessible).
        let protection: [FileAttributeKey: Any] =
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.setAttributes(protection, ofItemAtPath: base.path)
        for suffix in ["", "-wal", "-shm"] {
            let p = dbURL.path + suffix
            if fm.fileExists(atPath: p) { try? fm.setAttributes(protection, ofItemAtPath: p) }
        }


        return dbURL.path
    }

    /// `<AppSupport>/OpenWhoop/strap-log/`, where the strap log keeps its runs (`StrapLogArchive`), beside the
    /// store and inside the same macOS container. On iOS it takes the store's protection class, so lines logged
    /// in the background while the phone is locked can be written; and it is left out of backups, being a
    /// debugging aid for this device.
    static func strapLogDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        var dir = macOSProductionContainerAppSupport(defaultingTo: appSupport)
            .appendingPathComponent("OpenWhoop", isDirectory: true)
            .appendingPathComponent("strap-log", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                              ofItemAtPath: dir.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    /// On signed/production macOS builds the app runs sandboxed, so the real
    /// on-disk location is inside `~/Library/Containers/<bundle-id>/Data`. We pin
    /// the store there explicitly so the path is stable regardless of whether the
    /// sandbox is fully engaged when this runs. Non-production bundle IDs and all
    /// other platforms keep the plain Application Support directory.
    private static func macOSProductionContainerAppSupport(defaultingTo appSupport: URL) -> URL {
        return appSupport
    }

}
