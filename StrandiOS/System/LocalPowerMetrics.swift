import Foundation
import MetricKit
import OSLog

/// Apple delivers these reports locally. Capture runs only at launch and on delivery, without polling.
final class LocalPowerMetrics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = LocalPowerMetrics()
    private let queue = DispatchQueue(label: "com.noop.local-power-metrics", qos: .utility)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noopapp.noop", category: "LocalPowerMetrics")

    @MainActor
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            archive(payload.jsonRepresentation(), kind: .metrics, windowEnd: payload.timeStampEnd)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            archive(payload.jsonRepresentation(), kind: .diagnostics, windowEnd: payload.timeStampEnd)
        }
    }

    private func archive(_ data: Data, kind: LocalMetricReportArchive.Kind, windowEnd: Date) {
        queue.async { [self] in
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let archive = LocalMetricReportArchive(directory: documents.appendingPathComponent("Diagnostics/MetricKit"))
                try archive.save(data, kind: kind, windowEnd: windowEnd)
            } catch {
                logger.error("Local MetricKit archive failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
