import SwiftUI
import StrandDesign
import WhoopStore

// What the two exercise pickers share: the program line editor (`LiftProgramItemSheet`) and the running
// session's Add exercise sheet (`LiftSessionExerciseSheet`). The user's own exercise names offered back,
// a name remembered with its muscles, and the muscle classification itself — one copy of each, so the two
// pickers cannot drift about what a name is or which muscles it works.

/// The user's own exercise names (`liftExercise`), as the pickers read and write them.
enum LiftExerciseVocabulary {

    /// Names matching what has been typed so far, minus an exact match (no point suggesting the thing
    /// already in the box), most recently used first as the store orders them. Capped — this is a hint,
    /// not a browser.
    static func suggestions(_ vocabulary: [LiftExerciseRow], matching typed: String,
                            limit: Int = 6) -> [LiftExerciseRow] {
        let query = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Array(vocabulary.prefix(limit)) }
        return Array(vocabulary
            .filter { $0.name.lowercased().contains(query) && $0.name.lowercased() != query }
            .prefix(limit))
    }

    /// Remember `name` with its muscles, so it is offered back next time. `upsertLiftExercises` is keyed
    /// on (deviceId, name), so a known name is updated — its muscles, and when it was last used — never
    /// duplicated. Throws `WhoopStore.LiftExerciseVocabularyFull` for a NEW name once the vocabulary is
    /// full, which the caller explains rather than dropping the name silently.
    static func remember(_ name: String, primary: LiftMuscle?, secondaries: [LiftMuscle],
                         known vocabulary: [LiftExerciseRow], deviceId: String,
                         in store: WhoopStore) async throws {
        let now = Int(Date().timeIntervalSince1970)
        let existing = vocabulary.first { $0.name == name }
        _ = try await store.upsertLiftExercises([LiftExerciseRow(
            id: existing?.id ?? UUID().uuidString,
            deviceId: deviceId,
            name: name,
            primaryMuscle: primary,
            secondaryMuscles: secondaries,
            createdAt: existing?.createdAt ?? now,
            lastUsedTs: now)])
    }

    /// Secondaries in the vocabulary's canonical order rather than `Set` iteration order, so the stored
    /// list is stable between saves instead of reshuffling on every edit.
    static func ordered(_ secondaries: Set<LiftMuscle>, excluding primary: LiftMuscle?) -> [LiftMuscle] {
        LiftMuscle.ordered.filter { secondaries.contains($0) && $0 != primary }
    }
}
