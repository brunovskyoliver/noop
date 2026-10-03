import Foundation

/// Keeps the first passive reconnect pending until the disconnect handler can submit it.
/// Later attempts retain the bond-loop cooldown to avoid a connect/refuse loop.
struct BondLoopRecovery {
    static let retryFloor: TimeInterval = 10 * 60
    private var initialConnectPending = false

    static func shouldAttempt(paused: Bool, connected: Bool, intentionalDisconnect: Bool,
                              secondsSincePause: TimeInterval?) -> Bool {
        guard paused, !connected, !intentionalDisconnect else { return false }
        return secondsSincePause.map { $0 >= retryFloor } ?? true
    }

    mutating func parkIfDue(paused: Bool, connected: Bool, intentionalDisconnect: Bool,
                           secondsSincePause: TimeInterval?, justTripped: Bool = false,
                           park: () -> Bool) -> Bool {
        if justTripped { initialConnectPending = true }
        guard Self.shouldAttempt(paused: paused, connected: connected,
                                 intentionalDisconnect: intentionalDisconnect,
                                 secondsSincePause: initialConnectPending ? nil : secondsSincePause) else { return false }
        guard park() else { return false }
        initialConnectPending = false
        return true
    }

    mutating func reset() { initialConnectPending = false }
}
