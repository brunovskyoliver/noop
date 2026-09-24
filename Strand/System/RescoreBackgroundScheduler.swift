import Foundation
import OSLog
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Coordinates durable pending analysis and the execution time iOS grants it.
/// Short passes use an execution assertion; longer work is submitted to BGProcessing.
/// Processing delivery is discretionary, so the foreground path must also drain pending work.
/// Register before launch finishes and keep the processing identifier in the app's Info.plist.
@MainActor
enum RescoreBackgroundScheduler {

    @TaskLocal static var hasExtendedProcessingTime = false
    @TaskLocal static var hasExecutionGrant = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.noopapp.noop",
                                       category: "RescoreBackground")

    /// A re-score is OWED: either a pass marked itself started and never marked itself finished (it was
    /// killed), or a trigger deferred one to a background task. Survives process death, which is the
    /// entire point — the process being killed is the event we are trying to observe, and it is not an
    /// event the killed process gets any chance to write down.
    static let owedKey = "noop.rescoreOwed"
    /// Seconds the last COMPLETED pass took. Only ever written by a pass that reached the end.
    static let lastPassSecondsKey = "noop.rescoreLastPassSeconds"

    /// Identifies the MOST RECENT debt, so a pass can tell its own from someone else's (#1681).
    ///
    /// A token rather than a counter, deliberately. A counter needs read-modify-write, and two triggers
    /// marking a debt at the same moment could both read N and both write N+1 — losing an increment, and
    /// with it exactly the debt this is meant to protect. A fresh token is a single write: concurrent
    /// marks each produce a distinct one, the last wins, and it cannot equal any pass's captured token.
    static let owedTokenKey = "noop.rescoreOwedToken"

    /// Whether the outstanding debt was left by a pass that COMPLETED but could not settle, as opposed to
    /// one that was killed partway.
    ///
    /// #2238: the two are not the same question, and `isRescoreOwed` alone cannot tell them apart. A killed
    /// pass deliberately never advanced `analyzeWatermarkKey`, so its resume must force. A pass that
    /// completed and was merely out-voted by a newer token DID advance the watermark on its way out, so its
    /// resume can ask the fingerprint whether anything actually changed and stand down when nothing did.
    ///
    /// Forcing both is what lets an Oura ring draining every 5 minutes re-score 21 nights back to back for
    /// as long as the app is awake: each pass outlives its own debt, the resume forces a fresh one, and the
    /// chain never reaches a quiet interval it can stop at.
    static let owedAfterCompletedPassKey = "noop.rescoreOwedAfterCompletedPass"

    static var isRescoreOwed: Bool { UserDefaults.standard.bool(forKey: owedKey) }

    /// True only while the outstanding debt came from a completed-but-unsettled pass. Cleared by the next
    /// `markRescoreOwed()`, so a debt recorded by a pass that then dies reverts to forcing.
    static var isOwedAfterCompletedPass: Bool {
        UserDefaults.standard.bool(forKey: owedAfterCompletedPassKey)
    }

    static var currentOwedToken: String? { UserDefaults.standard.string(forKey: owedTokenKey) }

    static var lastCompletedPassSeconds: Double? {
        guard UserDefaults.standard.object(forKey: lastPassSecondsKey) != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: lastPassSecondsKey)
        return value.isFinite && value > 0 ? value : nil
    }

    /// When the last pass started (unix seconds), written only by a pass that is about to work, never by
    /// the deferral path, so repeated deferrals cannot keep a stale debt looking fresh.
    static let lastAttemptStartedAtKey = "noop.rescoreLastAttemptStartedAt"

    /// Seconds since the last pass started, nil if none was ever recorded.
    static var secondsSinceLastAttempt: Double? {
        let started = UserDefaults.standard.double(forKey: lastAttemptStartedAtKey)
        return started > 0 ? Date().timeIntervalSince1970 - started : nil
    }

    /// Mark a re-score as owed. Called by `IntelligenceEngine` once a pass is past every gate and is
    /// definitely about to work — so that a kill leaves the debt behind — and by the deferral path, where
    /// no pass is attempted at all but the work is just as outstanding.
    /// Returns the token stamped on this debt. A pass keeps it and hands it back at completion; every
    /// other caller (the deferral path) can ignore it, since it is not the one that will settle up.
    /// - Parameter passStarting: the caller is a pass about to work (not the deferral path), so the attempt
    ///   time is recorded for `RescoreBackgroundPolicy.interruptedRetryCooldownSeconds`.
    @discardableResult
    static func markRescoreOwed(passStarting: Bool = false) -> String {
        let token = UUID().uuidString
        if passStarting {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAttemptStartedAtKey)
        }
        UserDefaults.standard.set(true, forKey: owedKey)
        UserDefaults.standard.set(token, forKey: owedTokenKey)
        // A fresh debt is unproven until the pass that owns it finishes: if THIS pass is killed, the
        // watermark never advances and its resume must force. Cleared here rather than at completion so
        // the flag describes the CURRENT debt, never the previous one (#2238).
        UserDefaults.standard.set(false, forKey: owedAfterCompletedPassKey)
        return token
    }

    /// May a pass holding [capturedToken] settle the debt?
    ///
    /// Only if nothing newer was recorded while it ran. The bug in #1681 is that this question was never
    /// asked: completion cleared one global boolean unconditionally, so a trigger firing mid-pass — for
    /// data that arrived AFTER the pass had already read its inputs — had its debt erased before the
    /// correction it was recorded for ever ran. The scoring loop starts at today, so the night most
    /// likely to still be syncing is the first thing read and the likeliest to be caught mid-write.
    ///
    /// A pass with NO token never settles. That errs toward one extra pass, which costs battery; the
    /// other direction costs a night's scores until something unrelated happens to re-score it, which is
    /// the failure being fixed.
    ///
    /// Pure, so the rule is pinned without UserDefaults or a background task.
    static func maySettleDebt(capturedToken: String?, currentToken: String?) -> Bool {
        guard let capturedToken, !capturedToken.isEmpty else { return false }
        return capturedToken == currentToken
    }

    /// Settle the debt at the end of a completed pass, beside the watermark advance. A pass that is
    /// killed never reaches this, which is what leaves the mark set for the next launch to find.
    /// [owedToken] is the token this pass received from its own `markRescoreOwed()`. The debt is settled
    /// only if it is still the current one — see `maySettleDebt`. The pass duration is recorded either
    /// way: it is telemetry about THIS pass, and true regardless of whose debt is now outstanding.
    /// Returns whether the debt was actually settled, so the caller can SAY when it was not. Declining
    /// is the interesting outcome and it must not be silent: #1538 cost three nights because the log
    /// recorded that scoring had not happened without ever recording why, and a pass that completes
    /// while leaving the mark set looks identical to one that cleared it unless something says so.
    @discardableResult
    static func markRescoreCompleted(seconds: Double, owedToken: String?) -> Bool {
        let settled = maySettleDebt(capturedToken: owedToken, currentToken: currentOwedToken)
        if settled {
            UserDefaults.standard.set(false, forKey: owedKey)
        } else {
            // #2238: this pass finished and advanced the watermark; only a newer token outvoted it. Record
            // that, so the resume can gate on the fingerprint instead of forcing a pass whose inputs may be
            // byte-identical to the one that just ran.
            UserDefaults.standard.set(true, forKey: owedAfterCompletedPassKey)
        }
        if seconds.isFinite, seconds > 0 {
            UserDefaults.standard.set(seconds, forKey: lastPassSecondsKey)
        }
        return settled
    }

    /// Whether the app is somewhere a long pass might not survive. Always false on macOS — see the type doc.
    ///
    /// Anything that is not `.active` counts, `.inactive` included, which is the conservative direction on
    /// purpose. `.inactive` is the state on the way to suspension, so reading it as "foreground" is the
    /// error that loses work; reading it as "background" costs at most a deferral that the very next
    /// `.active` transition drains. The transient `.inactive` cases — app switcher, notification centre,
    /// an incoming call — therefore self-correct within seconds, and the case that matters is never missed.
    static var isBackgrounded: Bool {
        #if os(iOS)
        return UIApplication.shared.applicationState != .active
        #else
        return false
        #endif
    }

    /// Decide, then either run `work` under an execution assertion or leave it for `BGProcessingTask`.
    ///
    /// `log` goes to the strap log, always — both the decision and its reason. #1538 cost three nights
    /// because the log recorded that scoring had not happened without ever recording why.
    /// `isBackground` defaults to the real application state and is a parameter only so a test can drive
    /// the deferral branch, which is unreachable on macOS (where `isBackgrounded` is always false) and is
    /// exactly where the work-is-owed bookkeeping lives.
    /// - Parameter owesOnDefer: whether a deferral should record a debt for a background task to settle.
    ///   True for a real update path — a completed offload MUST eventually be scored, so deferring it has
    ///   to leave something behind or the work is dropped rather than moved. FALSE for the steady-state
    ///   backstop tick, which by its own contract is not the thing that must happen: every real update
    ///   forces its own pass, so the tick exists only to catch what those missed. Recording a debt for it
    ///   would conjure a forced full pass for a processing task to run when very likely nothing changed,
    ///   which is the churn #1146 exists to avoid. A debt an earlier real pass already recorded is
    ///   untouched either way.
    /// - Parameter passInProgress: a pass is already running in this process; see
    ///   `RescoreBackgroundPolicy.decide`.
    static func run(isBackground: Bool? = nil,
                    owesOnDefer: Bool = true,
                    passInProgress: Bool = false,
                    log: @escaping (String) -> Void,
                    work: @escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else { return }
        if hasExtendedProcessingTime {
            await runCancellableWork(work: work)
            return
        }
        let decision = RescoreBackgroundPolicy.decide(
            isBackground: isBackground ?? isBackgrounded,
            isRealUpdate: owesOnDefer,
            rescoreAlreadyOwed: isRescoreOwed,
            passInProgress: passInProgress,
            secondsSinceLastAttempt: secondsSinceLastAttempt)

        switch decision {
        case .deferToBackgroundTask(let reason):
            guard owesOnDefer else {
                // Nothing is queued and nothing is owed: the backstop simply does not run here. Said
                // plainly in the log, because "deferred" would promise a background task that is not
                // coming.
                log("re-score: backstop tick skipped while backgrounded — \(reason)")
                return
            }
            // Record the debt BEFORE scheduling. Without this the background task wakes, finds nothing
            // marked owed, and returns having done nothing — the deferral would silently drop the work
            // rather than move it.
            markRescoreOwed()
            log("re-score: deferred to a background task — \(reason)")
            schedule(log: log)
        case .run:
            await withAssertion(log: log, work: work)
        }
    }

    /// How many times the re-score execution assertion has expired in this process. A pass reads it at its
    /// start and end, so its cost line can say whether it outlived its background grant.
    private(set) static var assertionExpiries = 0

    /// CPU seconds this process has used, user plus system, across all threads. Process-wide, so it includes
    /// the BLE and UI work beside a pass; nil if the kernel refuses the read.
    nonisolated static func processCPUSeconds() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// What a completed pass cost, and whether it outlived its background grant.
    ///
    /// The `re-score: done` duration is uptime, which keeps running while the process is suspended, so on
    /// its own it cannot separate a pass that was suspended and resumed across wakes from one that ran on
    /// past an expired assertion. CPU time beside it can: a pass that spends a small fraction of its elapsed
    /// time on CPU was mostly suspended, and `expired` says whether the assertion ran out on the way.
    nonisolated static func passCostLogLine(cpuSeconds: Double?, elapsedSeconds: Double,
                                            assertionExpiries: Int, backgroundedAtEnd: Bool) -> String {
        let cpu = cpuSeconds.map { String(format: "%.1fs", max(0, $0)) } ?? "n/a"
        let share = cpuSeconds.flatMap { elapsedSeconds > 0 ? Int((max(0, $0) / elapsedSeconds * 100).rounded()) : nil }
        return "re-score: cost cpu=\(cpu) elapsed=\(String(format: "%.1f", elapsedSeconds))s"
            + " cpuShare=\(share.map { "\($0)%" } ?? "n/a") assertionExpired=\(assertionExpiries)"
            + " backgrounded=\(backgroundedAtEnd)"
    }

    /// Rest between units of re-score work when backgrounded, so the pass stays under iOS's background CPU
    /// limit instead of being killed by it (`RescoreBackgroundPolicy.backgroundRestPerWorkSecond`). `mark` is
    /// the uptime the work since the last rest started at, in nanoseconds. It is left alone until a quantum of
    /// work has built up (`backgroundWorkQuantumSeconds`), so short units run back to back, and it is reset
    /// after a rest or in the foreground.
    nonisolated static func paceIfBackgrounded(since mark: inout UInt64) async {
        let workSeconds = Double(DispatchTime.now().uptimeNanoseconds &- mark) / 1_000_000_000
        let background = await MainActor.run { isBackgrounded }
        let rest = RescoreBackgroundPolicy.restSeconds(afterWorkSeconds: workSeconds, isBackground: background)
        if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
        if rest > 0 || !background { mark = DispatchTime.now().uptimeNanoseconds }
    }

    /// Cancellation must reach the worker, including when the caller was already cancelled.
    /// Analysis must likewise propagate it to any detached CPU task it owns.
    static func runCancellableWork(work: @escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else { return }
        let worker = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await $hasExecutionGrant.withValue(true) { await work() }
        }
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Expiration cancels the actual worker before releasing the execution assertion.
    private static func withAssertion(log: @escaping (String) -> Void,
                                      work: @escaping @MainActor () async -> Void) async {
        #if os(iOS)
        let worker = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await $hasExecutionGrant.withValue(true) { await work() }
        }
        let assertion = BackgroundAssertion()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "noop.rescore") {
            MainActor.assumeIsolated {
                assertionExpiries += 1
                worker.cancel()
                markRescoreOwed()
                log("re-score: background time expired; cancelling and preserving pending work")
                schedule(log: log)
                assertion.end()
            }
        }
        assertion.store(taskID)
        if taskID == .invalid && isBackgrounded {
            worker.cancel()
            markRescoreOwed()
            log("re-score: execution assertion unavailable; preserving pending work")
            schedule(log: log)
        }
        // Leave headroom before iOS's expiration callback. This timer only bounds work that
        // started in the background; foreground work remains eligible to finish normally.
        let budget: Task<Void, Never>? = isBackgrounded ? Task {
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard isBackgrounded else { return }
            worker.cancel()
            markRescoreOwed()
            log("re-score: short background budget used; saved checkpoints will resume later")
            schedule(log: log)
        } : nil
        defer { budget?.cancel() }
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        assertion.end()
        #else
        await runCancellableWork(work: work)
        #endif
    }

    // MARK: - iOS background-processing plumbing

    #if os(iOS)
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".rescore"

    /// Register the handler. MUST be called from `StrandiOSApp.init()` before launch finishes, and the
    /// identifier MUST be listed in `BGTaskSchedulerPermittedIdentifiers`, or iOS never delivers the task.
    /// Safe to leave uncalled: `schedule()` fails gracefully and the foreground path still scores.
    /// `onExpire` reports iOS reclaiming the processing time before the pass finished. The pass keeps no
    /// record of it otherwise, so a strap log that simply stops mid-night cannot say why.
    static func register(perform operation: @escaping @MainActor () async -> Void,
                         onExpire: @escaping @MainActor () -> Void = {}) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let completion = TaskCompletionGuard(task: task)
            let worker = Task { @MainActor in
                await $hasExtendedProcessingTime.withValue(true) {
                    guard !Task.isCancelled else { return }
                    await operation()
                }
                guard !Task.isCancelled else {
                    if isRescoreOwed { schedule() }
                    completion.finish(success: false)
                    return
                }
                // Re-arm only while work remains. A processing task is single-shot, and re-submitting
                // unconditionally would ask iOS for a wake on every install forever, including the ones
                // that never have anything to do.
                if isRescoreOwed { schedule() }
                completion.finish(success: !isRescoreOwed)
            }
            task.expirationHandler = {
                worker.cancel()
                Task { @MainActor in onExpire() }
                // The pass did not finish inside the processing budget either. Ask for another rather
                // than dropping the work, and report the failure so iOS's own scheduling heuristics see
                // it honestly instead of being told this succeeded.
                Task { @MainActor in
                    schedule()
                }
                completion.finish(success: false)
            }
        }
    }

    /// Keep exactly one pending request, so calling this from several places is idempotent and also
    /// repairs a request the system discarded.
    static func schedule(log: ((String) -> Void)? = nil) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        // Neither is required. Network is irrelevant to an offline app, and demanding external power
        // would strand the work for anyone who does not charge overnight — the exact population most
        // likely to be wearing the strap continuously.
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            let message = "re-score: background task submission failed: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            log?(message)
        }
    }

    /// Holds the background-task identifier so the normal path and the expiry handler can each try to end
    /// it while exactly one of them succeeds. UIKit treats a double `endBackgroundTask` as a programmer
    /// error and a never-ended one as grounds for killing the app, so neither may be left to ordering.
    /// Plain lock rather than actor isolation, matching `TaskCompletionGuard` below.
    private final class BackgroundAssertion: @unchecked Sendable {
        private let lock = NSLock()
        private var id: UIBackgroundTaskIdentifier = .invalid
        private var ended = false

        @MainActor func store(_ newID: UIBackgroundTaskIdentifier) {
            lock.lock()
            let alreadyEnded = ended
            if !alreadyEnded { id = newID }
            lock.unlock()
            // Expiration can arrive before beginBackgroundTask returns its identifier.
            if alreadyEnded, newID != .invalid {
                UIApplication.shared.endBackgroundTask(newID)
            }
        }

        @MainActor func end() {
            lock.lock()
            let current = id
            id = .invalid
            ended = true
            lock.unlock()
            guard current != .invalid else { return }
            UIApplication.shared.endBackgroundTask(current)
        }
    }

    /// Guards `setTaskCompleted` against being called twice — once normally and once from the expiration
    /// handler — which `BGTaskScheduler` treats as a programmer error. Plain lock rather than actor
    /// isolation: iOS can invoke the expiration handler on a different queue. Mirrors the guard in
    /// `ScheduledDebugExport`.
    private final class TaskCompletionGuard: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var finished = false

        init(task: BGTask) { self.task = task }

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
        }
    }
    #else
    /// macOS has no background-task scheduler and no suspension deadline — nothing to schedule.
    static func schedule(log: ((String) -> Void)? = nil) {}
    #endif
}
