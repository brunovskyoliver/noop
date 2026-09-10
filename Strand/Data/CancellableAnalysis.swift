import Foundation

/// Own the detached task so expiration can reach CPU work instead of cancelling only its waiter.
enum CancellableAnalysis {
    static func run<Value>(_ operation: @escaping @Sendable () async -> Value) async -> Value {
        let worker = Task.detached(priority: .utility) { await operation() }
        return await withTaskCancellationHandler {
            if Task.isCancelled { worker.cancel() }
            return await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
