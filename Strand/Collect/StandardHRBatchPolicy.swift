/// Bounds live persistence by accepted readings and elapsed time. R-R rows do not shorten the
/// normal batch; the row cap bounds unusually dense notifications.
enum StandardHRBatchPolicy {
    static let maxReadings = 30
    static let maxRows = 256
    static let maxIntervalSeconds: Double = 30

    static func shouldFlush(readings: Int, rows: Int, elapsedSeconds: Double) -> Bool {
        guard rows > 0 else { return false }
        return readings >= maxReadings || rows >= maxRows
            || (elapsedSeconds.isFinite && elapsedSeconds >= maxIntervalSeconds)
    }
}
