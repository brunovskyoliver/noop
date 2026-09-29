#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Add an exercise to the running session, WHOOP's "+" in the session header over the classic
/// `LiftSessionExerciseSheet` rules: one done before, or a new name with its muscles, remembered like a
/// name typed into the builder. It joins the session with one set at 0 kg × 0 reps; finishing asks
/// whether the program keeps it.
struct BroopFinalBLiftExerciseSheet: View {
    let onAdd: (_ name: String, _ primary: LiftMuscle?, _ secondaries: [LiftMuscle]) -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var exercise = ""
    @State private var primary: LiftMuscle?
    @State private var secondaries: Set<LiftMuscle> = []
    @State private var vocabulary: [LiftExerciseRow] = []
    @State private var vocabularyFullLimit: Int?
    @State private var adding = false

    private var trimmedExercise: String { exercise.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmedExercise.isEmpty && !adding }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BroopFinalBFieldLabel(text: String(localized: "Exercise name"))
                    TextField("", text: $exercise, prompt: Text("Incline dumbbell press").foregroundColor(BroopPalette.textTertiary))
                        .broopFinalBInputBox()
                        .padding(.top, 8)
                        .accessibilityLabel(Text("Exercise name"))
                    BroopFinalBNote(text: String(localized: "Pick one you have done before, or type a new name."))
                        .padding(.top, 8)

                    let suggestions = LiftExerciseVocabulary.suggestions(vocabulary, matching: exercise, limit: 8)
                    if !suggestions.isEmpty {
                        BroopFinalBFieldLabel(text: String(localized: "Used before")).padding(.top, 20)
                        VStack(spacing: 8) {
                            ForEach(suggestions, id: \.id) { row in
                                BroopFinalBExerciseSuggestion(row: row, onAdopt: { adopt(row) })
                            }
                        }
                        .padding(.top, 8)
                    }

                    BroopFinalBMusclePicker(primary: $primary, secondaries: $secondaries).padding(.top, 30)

                    BroopFinalBNote(text: String(localized: "It joins this session with one set, its weight and reps at 0 until you type what you lift. Finishing asks whether the program keeps it."))
                        .padding(.top, 24)
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .broopFinalBBottomCTA {
                BroopActivityButton(title: String(localized: "Add to session"), kind: .mint, height: 56) { Task { await add() } }
                    .disabled(!canAdd)
            }
            .broopFinalBSheetChrome(String(localized: "Add exercise"), onClose: { dismiss() })
            .broopFinalBKeyboardDone()
        }
        .presentationDragIndicator(.visible)
        .task { await load() }
        // A name typed out in full that is already known brings its muscles, unless muscles were chosen.
        .onChange(of: exercise) { _, _ in
            guard primary == nil, secondaries.isEmpty,
                  let known = vocabulary.first(where: { $0.name == trimmedExercise }) else { return }
            primary = known.primaryMuscle
            secondaries = Set(known.secondaryMuscles)
        }
        .broopFinalBVocabularyFullAlert($vocabularyFullLimit)
    }

    private func adopt(_ row: LiftExerciseRow) {
        exercise = row.name
        primary = row.primaryMuscle
        secondaries = Set(row.secondaryMuscles)
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
    }

    private func add() async {
        guard canAdd else { return }
        adding = true
        defer { adding = false }
        let name = trimmedExercise
        let ordered = LiftExerciseVocabulary.ordered(secondaries, excluding: primary)
        if let store = await repo.storeHandle() {
            do {
                try await LiftExerciseVocabulary.remember(name, primary: primary, secondaries: ordered,
                                                          known: vocabulary, deviceId: repo.deviceId, in: store)
            } catch let full as WhoopStore.LiftExerciseVocabularyFull {
                vocabularyFullLimit = full.limit
                return
            } catch {
                // Still added: every saved set carries its own copy of the name and muscles.
            }
        }
        onAdd(name, primary, ordered)
        dismiss()
    }
}
#endif
