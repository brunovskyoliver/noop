import WhoopProtocol

/// Recorded HR seconds in an explicit half-open window. This measures input completeness,
/// not wear, optical quality or the accuracy of an inferred activity.
public struct HRInputCoverage: Codable, Equatable, Sendable {
    public let recordedSeconds: Int
    public let expectedSeconds: Int
    public let longestGapSeconds: Int
    public var fraction: Double {
        expectedSeconds > 0 ? Double(recordedSeconds) / Double(expectedSeconds) : 0
    }
    /// Conservative display policy, not an empirically calibrated probability of accuracy.
    public var isComplete: Bool { fraction >= 0.95 && longestGapSeconds <= 300 }

    public init(samples: [HRSample], window: Range<Int>) {
        let seconds = Set(samples.lazy.filter {
            window.contains($0.ts) && (25...250).contains($0.bpm)
        }.map(\.ts)).sorted()
        recordedSeconds = seconds.count
        expectedSeconds = window.count
        var cursor = window.lowerBound
        var gap = 0
        for second in seconds {
            gap = max(gap, second - cursor)
            cursor = second + 1
        }
        longestGapSeconds = max(gap, window.upperBound - cursor)
    }
}
