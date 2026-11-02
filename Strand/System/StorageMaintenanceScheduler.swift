import BackgroundTasks
import Foundation

/// Nightly store trim and the one-off rebuild, on external power so a multi-gigabyte rewrite never
/// spends the battery. The daily trim also runs when the app opens, so a phone that never gets this wake
/// still stays within retention.
enum StorageMaintenanceScheduler {
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".storagemaint"

    /// Must be called before launch finishes, and the identifier must be permitted in project.yml.
    static func register(perform operation: @escaping @MainActor (@escaping @Sendable () -> Bool) async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            schedule()
            let worker = Task { @MainActor in
                await operation { !Task.isCancelled }
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { worker.cancel() }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3_600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
