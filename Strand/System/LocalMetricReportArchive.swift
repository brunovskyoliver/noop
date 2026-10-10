import CryptoKit
import Foundation

/// Retains original Apple report bytes locally, deduplicated and bounded by count and size.
/// Callers serialize writes; reporting windows determine retention even when delivery is delayed.
struct LocalMetricReportArchive: Sendable {
    enum Kind: String { case metrics, diagnostics }
    enum ArchiveError: Error { case payloadTooLarge, invalidWindow }

    let directory: URL
    var maxReports = 32
    var maxBytes = 8 * 1024 * 1024

    func save(_ data: Data, kind: Kind, windowEnd: Date) throws {
        guard data.count <= maxBytes else { throw ArchiveError.payloadTooLarge }
        let milliseconds = windowEnd.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds >= 0,
              milliseconds < Double(Int64.max) else { throw ArchiveError.invalidWindow }
        let end = Int64(milliseconds.rounded(.down))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent("\(kind.rawValue)-\(end)-\(hash).json")
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var localDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try localDirectory.setResourceValues(resourceValues)
        #endif
        if !fm.fileExists(atPath: file.path) {
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
        }
        let files = try fm.contentsOfDirectory(at: directory,
                                               includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        let reports = try files.compactMap { url -> (url: URL, end: Int64, bytes: Int)? in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard url.pathExtension == "json", parts.count == 3,
                  Kind(rawValue: String(parts[0])) != nil, let end = Int64(parts[1]) else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return (url, end, values.fileSize ?? 0)
        }.sorted { $0.end == $1.end ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.end > $1.end }
        var retainedBytes = 0
        for (index, report) in reports.enumerated() {
            if index < maxReports, retainedBytes + report.bytes <= maxBytes {
                retainedBytes += report.bytes
            } else {
                try fm.removeItem(at: report.url)
            }
        }
    }
}
