import Combine
import Foundation
import OSLog
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// A finite catch-up requested by a person. Automatic Bluetooth sync does not use this controller.
@MainActor
final class SyncCatchUpTask: ObservableObject {
    typealias Report = @MainActor (Int, String) -> Void
    typealias Operation = @MainActor (@escaping Report) async -> Bool

    @Published private(set) var isRunning = false
    @Published private(set) var status: String?

    private var worker: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var operation: Operation?
    private var requestID: String?
    private var updateSystemProgress: ((Int, String) -> Void)?
    private var finishSystemTask: ((Bool) -> Void)?
    private var registered = false
    private var requiresForeground = false
    private static let identifierPrefix = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".catchup."
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noopapp.noop", category: "SyncCatchUp")

    func start(operation: @escaping Operation) {
        guard !isRunning else { return }
        requiresForeground = false
        self.operation = operation
        isRunning = true
        status = "Starting catch-up…"
        let id = Self.identifierPrefix + UUID().uuidString
        requestID = id
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.cancel(message: "Catch-up paused. Saved history is kept; remaining work can resume later.")
        }
        #if os(iOS)
        if #available(iOS 26.0, *), UIApplication.shared.applicationState == .active {
            if !registered {
                registered = BGTaskScheduler.shared.register(
                    forTaskWithIdentifier: Self.identifierPrefix + "*", using: .main
                ) { [weak self] task in
                    Task { @MainActor in
                        guard let self, let continued = task as? BGContinuedProcessingTask,
                              self.isRunning, self.requestID == task.identifier else {
                            task.setTaskCompleted(success: false)
                            return
                        }
                        self.attach(continued)
                    }
                }
            }
            if registered {
                let request = BGContinuedProcessingTaskRequest(
                    identifier: id, title: "Sync strap history", subtitle: "Starting catch-up…")
                // A queued task could surprise the user much later. If unavailable, use normal execution.
                request.strategy = .fail
                do {
                    try BGTaskScheduler.shared.submit(request)
                    return
                } catch {
                    logger.error("Continued catch-up unavailable: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                logger.error("Continued catch-up handler registration failed")
            }
            requiresForeground = true
            status = "Background catch-up unavailable; keep NOOP open to finish."
        }
        #endif
        launch(id: id, extended: false)
    }

    func cancel() {
        cancel(message: "Catch-up paused. Saved history is kept; remaining work can resume later.")
    }

    private func cancel(message: String) {
        guard isRunning else { return }
        worker?.cancel()
        #if os(iOS)
        if let requestID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestID) }
        #endif
        finish(success: false, message: message)
    }

    private func launch(id: String, extended: Bool) {
        guard let operation, worker == nil, requestID == id else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            let success = await RescoreBackgroundScheduler.$hasExtendedProcessingTime.withValue(extended) {
                await operation { [weak self] units, message in
                    guard let self, self.requestID == id else { return }
                    self.status = self.requiresForeground ? message + " · Keep NOOP open" : message
                    self.updateSystemProgress?(max(0, units), message)
                }
            }
            guard self.requestID == id else { return }
            self.finish(success: success && !Task.isCancelled,
                        message: success && !Task.isCancelled ? "Catch-up complete" : "Catch-up paused; saved history is kept.")
        }
    }

    private func finish(success: Bool, message: String) {
        deadline?.cancel()
        deadline = nil
        finishSystemTask?(success)
        finishSystemTask = nil
        updateSystemProgress = nil
        operation = nil
        requestID = nil
        worker = nil
        isRunning = false
        status = message
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        guard let id = requestID else {
            task.setTaskCompleted(success: false)
            return
        }
        // The strap exposes committed chunks, not its total backlog. Keep the total indeterminate.
        task.progress.totalUnitCount = -1
        task.progress.completedUnitCount = 0
        updateSystemProgress = { units, message in
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(units))
            task.updateTitle("Sync strap history", subtitle: message)
        }
        finishSystemTask = { success in
            if success {
                let completed = max(1, task.progress.completedUnitCount)
                task.progress.totalUnitCount = completed
                task.progress.completedUnitCount = completed
            }
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.cancel(message: "Background catch-up ended. Saved history is kept.")
            }
        }
        launch(id: id, extended: true)
    }
    #endif
}
