import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// A bounded sync opportunity when iOS grants a refresh wake. Bluetooth events remain the
/// primary wake source; neither this request nor a timer guarantees a delivery time.
@MainActor
enum StrapSyncBackgroundScheduler {
    static let identifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".strapsync"

    static func perform(prepare: () -> Void, completed: () -> Bool,
                        wait: () async throws -> Void = { try await Task.sleep(nanoseconds: 1_000_000_000) },
                        attempts: Int = 25) async -> Bool {
        guard !Task.isCancelled else { return false }
        prepare()
        for _ in 0..<attempts {
            guard !Task.isCancelled else { return false }
            if completed() { return true }
            do { try await wait() } catch { return false }
        }
        return !Task.isCancelled && completed()
    }

    #if os(iOS)
    static func register(expected: @escaping @MainActor () -> Bool,
                         log: @escaping @MainActor (String) -> Void,
                         operation: @escaping @MainActor () async -> Bool) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let completion = Completion(task)
            let worker = Task { @MainActor in
                guard expected(), !Task.isCancelled else {
                    completion.finish(false)
                    return
                }
                schedule(expected: true, log: log)
                log("Background strap sync: refresh wake granted")
                let success = await operation()
                log("Background strap sync: \(success ? "offload completed" : "no completed offload during refresh wake; Bluetooth recovery remains pending")")
                completion.finish(success && !Task.isCancelled)
            }
            task.expirationHandler = {
                worker.cancel()
                completion.finish(false)
                Task { @MainActor in log("Background strap sync: refresh time expired") }
            }
        }
        if !registered { log("Background strap sync: handler registration failed") }
    }

    static func schedule(expected: Bool, log: (String) -> Void) {
        guard expected else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { log("Background strap sync: request rejected: \(error.localizedDescription)") }
    }

    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private let task: BGTask
        private var finished = false

        init(_ task: BGTask) { self.task = task }

        func finish(_ success: Bool) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            task.setTaskCompleted(success: success)
        }
    }
    #endif
}
