#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import WhoopStore

/// Build workouts from a spreadsheet, over the classic `LiftProgramImportSheet` rules: the file is
/// parsed and shown back as what it WILL create (workouts, their exercises, every warning), and nothing
/// is written until IMPORT is tapped. Same size limit, same accepted types, same writes.
struct BroopFinalBLiftImportSheet: View {
    var onImported: () async -> Void

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss

    @State private var picking = false
    @State private var parsed: LiftProgramImportResult?
    @State private var failure: String?
    @State private var importing = false

    private static let acceptedTypes: [UTType] = {
        var types: [UTType] = [.spreadsheet, .commaSeparatedText, .plainText, .data]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.insert(xlsx, at: 0) }
        return types
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let parsed { preview(parsed) } else { intro }
                    if let failure {
                        BroopActivityNotice(symbol: "exclamationmark.triangle.fill", text: failure, tint: BroopPalette.bandLow)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .broopFinalBBottomCTA { cta }
            .broopFinalBSheetChrome(String(localized: "Import workouts"), onClose: { dismiss() })
        }
        .presentationDragIndicator(.visible)
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.acceptedTypes,
                      allowsMultipleSelection: false) { handle($0) }
    }

    @ViewBuilder private var cta: some View {
        if let parsed, !parsed.programs.isEmpty {
            BroopActivityButton(title: parsed.programs.count == 1 ? String(localized: "Import 1 workout")
                                                                  : String(localized: "Import \(parsed.programs.count) workouts"),
                                kind: .mint, height: 56) { Task { await performImport(parsed) } }
                .disabled(importing)
        } else {
            BroopActivityButton(title: String(localized: "Choose a file"), symbol: "doc.badge.plus", kind: .mint, height: 56) {
                failure = nil
                picking = true
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "tablecells")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(BroopActivityPalette.mint)
                    .frame(width: 64, height: 50)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill it in on a computer").font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                    Text(verbatim: ".xlsx · .csv").font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
            BroopFinalBNote(text: String(localized: "Download the template from the NOOP repository, fill in one row per exercise, then bring the file here. Excel, Numbers, Google Sheets and LibreOffice all work: .xlsx or .csv."),
                            color: BroopPalette.textBody)
                .padding(.top, 20)
            BroopFinalBNote(text: String(localized: "Only the exercise name is required. Anything you leave blank can be filled in later, or during the session."))
                .padding(.top, 12)
            BroopFinalBNote(text: String(localized: "Nothing is saved until you check what the file will create and tap Import."))
                .padding(.top, 12)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    private func preview(_ result: LiftProgramImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopActivityDivider(title: String(localized: "What the file will create"))
            ForEach(Array(result.programs.enumerated()), id: \.offset) { _, program in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        BroopFinalBThumb(width: 64, height: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            BroopCaps(program.name, size: 12.5).lineLimit(2)
                            Text(verbatim: String(localized: "\(program.lines.count) exercises"))
                                .font(BroopType.medium(13)).foregroundStyle(BroopActivityPalette.mint)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Color(broopHex: 0x353A3F))
                    VStack(spacing: 0) {
                        ForEach(Array(program.lines.enumerated()), id: \.offset) { index, line in
                            if index > 0 { BroopHairline() }
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(verbatim: line.exercise).font(BroopType.medium(14)).foregroundStyle(BroopPalette.textPrimary)
                                Spacer(minLength: 8)
                                Text(verbatim: summary(line)).font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .background(BroopPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BroopPalette.warning)
                        BroopCaps(String(localized: "Worth checking"), size: 11, color: BroopPalette.warning)
                    }
                    // Listed in full: each names a row the user can go and fix.
                    ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, w in
                        BroopFinalBNote(text: w, color: BroopPalette.textBody)
                    }
                    BroopFinalBNote(text: String(localized: "These lines still import. Anything unclassified can be set in the app."))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.warning.opacity(0.10)))
            }

            BroopActivityButton(title: String(localized: "Choose a different file"), symbol: "arrow.triangle.2.circlepath",
                                kind: .grey, height: 46) {
                failure = nil
                parsed = nil
                picking = true
            }
            .padding(.top, 4)
        }
    }

    /// "3 x 10 · 50 kg · RPE ≤8 · 90s", skipping blanks (the classic preview's wording).
    private func summary(_ line: ImportedProgramLine) -> String {
        var parts: [String] = []
        if let sets = line.targetSets, let reps = line.targetReps { parts.append("\(sets) x \(reps)") }
        else if let sets = line.targetSets { parts.append("\(sets) x") }
        if let kg = line.targetWeightKg { parts.append(LiftFormat.trim(kg) + " kg") }
        if let rpe = line.targetMaxRpe { parts.append("RPE ≤" + LiftFormat.trim(rpe)) }
        if let rest = line.restSec { parts.append("\(rest)s") }
        return parts.joined(separator: " · ")
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            failure = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // Size first: reading an oversized file into memory is what the limit prevents.
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard bytes <= LiftProgramSheetImporter.maxFileBytes else {
                    parsed = nil
                    failure = message(for: .tooLarge)
                    return
                }
                let data = try Data(contentsOf: url)
                parsed = try LiftProgramSheetImporter.parse(data: data)
                failure = nil
            } catch let error as LiftProgramSheetImporter.ImportError {
                parsed = nil
                failure = message(for: error)
            } catch {
                parsed = nil
                failure = String(localized: "That file could not be read.")
            }
        }
    }

    private func message(for error: LiftProgramSheetImporter.ImportError) -> String {
        switch error {
        case .unreadable: return String(localized: "That does not look like a spreadsheet. Use the template, saved as .xlsx or .csv.")
        case .missingColumns: return String(localized: "That sheet has no Exercise column. Use the template — the import matches on the header names.")
        case .empty: return String(localized: "That sheet has no exercises in it yet.")
        case .tooLarge: return String(localized: "That file is too big to be a program sheet.")
        }
    }

    private func performImport(_ result: LiftProgramImportResult) async {
        guard !importing, let store = await repo.storeHandle() else { return }
        importing = true
        defer { importing = false }
        let now = Int(Date().timeIntervalSince1970)
        for program in result.programs {
            let programId = UUID().uuidString
            _ = try? await store.upsertLiftPrograms([LiftProgramRow(
                id: programId, deviceId: repo.deviceId, name: program.name, note: program.note,
                createdAt: now, updatedAt: now, archived: false)])
            let items = program.lines.enumerated().map { index, line in
                LiftProgramItemRow(id: UUID().uuidString, deviceId: repo.deviceId, programId: programId,
                                   ord: index, exercise: line.exercise, targetSets: line.targetSets,
                                   targetRepsLow: line.targetReps, targetRepsHigh: nil, targetRpe: line.targetMaxRpe,
                                   targetWeightKg: line.targetWeightKg, restSec: line.restSec, note: line.note)
            }
            _ = try? await store.replaceLiftProgramItems(programId: programId, items: items)
            // Best-effort: the vocabulary is capped, and hitting the cap must not fail the import.
            let exercises = program.lines.map { line in
                LiftExerciseRow(id: UUID().uuidString, deviceId: repo.deviceId, name: line.exercise,
                                primaryMuscle: line.primaryMuscle, secondaryMuscles: line.secondaryMuscles,
                                createdAt: now, lastUsedTs: nil)
            }
            _ = try? await store.upsertLiftExercises(exercises)
        }
        await onImported()
        dismiss()
    }
}
#endif
