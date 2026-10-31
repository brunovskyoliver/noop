#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Strength Trainer over the Lift Log: MY WORKOUTS lists the saved programs (start, edit, create,
/// import) and PROGRESS carries this week's sets per muscle and the finished sessions. The builder, the
/// spreadsheet import and a past session's detail are the native `BroopFinalBLift…` sheets over the
/// rules. Lifting never changes Effort, exactly as on the screen.
struct BroopActivityStrengthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.broopCloseHostSheet) private var closeHostSheet

    enum Tab: Hashable { case workouts, progress }
    @State private var tab: Tab = .workouts
    @State private var programs: [LiftProgramRow] = []
    @State private var history: [LiftSessionRow] = []
    @State private var weekCounts: [LiftMuscle: Double] = [:]
    @State private var loaded = false
    @State private var editing: ProgramTarget?
    @State private var importing = false
    @State private var viewing: SessionTarget?

    private struct ProgramTarget: Identifiable { let id: String; let program: LiftProgramRow? }
    private struct SessionTarget: Identifiable { let id: String; let session: LiftSessionRow }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BroopUnderlineTabs(options: [Tab.workouts, Tab.progress], selection: $tab) {
                    $0 == .workouts ? String(localized: "My workouts") : String(localized: "Progress")
                }
                .padding(.top, 14)
                if tab == .workouts { workoutsTab } else { progressTab }
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopActivityHeader(title: String(localized: "Strength trainer"), inBar: true, onBack: { dismiss() })
        }
        .broopActivityPage()
        .refreshable { await load() }
        .task(id: "\(repo.refreshSeq)-\(session.savedSessions)") { await load() }
        .sheet(item: $editing) { t in BroopFinalBLiftProgramEditor(program: t.program) { await load() } }
        .sheet(isPresented: $importing) { BroopFinalBLiftImportSheet { await load() } }
        .sheet(item: $viewing) { t in BroopFinalBLiftSessionDetail(session: t.session) { await load() } }
    }

    // MARK: My workouts

    @ViewBuilder private var workoutsTab: some View {
        if session.isActive {
            Button { Task { await openSession() } } label: {
                HStack(spacing: 12) {
                    Circle().fill(BroopActivityPalette.mint).frame(width: 8, height: 8)
                    BroopCaps(String(localized: "Session running"), size: 11, color: BroopActivityPalette.mint)
                    Text(verbatim: session.programName ?? "").font(BroopType.demi(14)).foregroundStyle(BroopPalette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(BroopActivityPalette.mintTint))
            }
            .buttonStyle(BroopPressableStyle())
            .padding(.top, 20)
        }

        if !loaded {
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if programs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                BroopCaps(String(localized: "No workouts yet"), size: 12)
                Text("A workout is a name and an ordered list of exercises with your targets: working sets, reps, weight, rest and your own technique note.")
                    .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))
            .padding(.top, 20)
        } else {
            VStack(spacing: 10) {
                ForEach(programs, id: \.id) { programRow($0) }
            }
            .padding(.top, 20)
        }

        VStack(spacing: 12) {
            BroopActivityButton(title: String(localized: "Create new workout"), kind: .mint, height: 54) {
                editing = ProgramTarget(id: "new", program: nil)
            }
            BroopActivityButton(title: String(localized: "Import from spreadsheet"), symbol: "tablecells", kind: .grey, height: 46) {
                importing = true
            }
        }
        .padding(.top, 24)

        Text("Lifting adds volume and set counts. It never changes your Effort, which stays measured from heart rate.")
            .font(BroopType.regular(12.5))
            .foregroundStyle(BroopPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
    }

    private func programRow(_ program: LiftProgramRow) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black)
                BroopMark().fill(style: FillStyle(eoFill: true)).foregroundStyle(BroopPalette.textSecondary)
                    .frame(width: 26, height: 26)
            }
            .frame(width: 64, height: 50)
            Button { editing = ProgramTarget(id: program.id, program: program) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: program.name).font(BroopType.demi(16)).foregroundStyle(BroopPalette.textPrimary)
                        .lineLimit(1)
                    if let note = program.note, !note.isEmpty {
                        Text(verbatim: note).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary).lineLimit(2)
                    } else {
                        Text("Tap to edit").font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { Task { await start(program) } } label: {
                BroopCaps(session.isActive ? String(localized: "Running") : String(localized: "Start"), size: 11,
                          color: BroopActivityPalette.mint)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Capsule().strokeBorder(BroopActivityPalette.mint, lineWidth: 1.5))
            }
            .buttonStyle(BroopPressableStyle())
            .accessibilityLabel(Text("Start this program"))
        }
        .padding(8)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
        .contextMenu {
            Button("Edit…") { editing = ProgramTarget(id: program.id, program: program) }
            Button("Start") { Task { await start(program) } }
        }
    }

    /// Snapshot the program into the session plan, as the Lift Log does.
    private func start(_ program: LiftProgramRow) async {
        guard let store = await repo.storeHandle() else { return }
        let items = (try? await store.liftProgramItems(programId: program.id)) ?? []
        guard !items.isEmpty else { return }
        let vocabulary = (try? await store.liftExercises(deviceId: repo.deviceId)) ?? []
        let plan = items.map { item -> LiftPlanItem in
            let known = vocabulary.first { $0.name == item.exercise }
            return LiftPlanItem(exercise: item.exercise, primaryMuscle: known?.primaryMuscle,
                                secondaryMuscles: known?.secondaryMuscles ?? [], targetSets: item.targetSets,
                                restSec: item.restSec, targetRepsLow: item.targetRepsLow, targetRepsHigh: item.targetRepsHigh,
                                targetRpe: item.targetRpe, targetWeightKg: item.targetWeightKg, note: item.note,
                                programItemId: item.id)
        }
        if !session.isActive {
            session.start(plan: plan, programId: program.id, programName: program.name)
        }
        await openSession()
    }

    /// Show the running session. The shell presents it; when this screen is itself a shell sheet (from
    /// the "+" menu), that sheet closes first so the session can take its place.
    private func openSession() async {
        guard let closeHostSheet else {
            session.isPresented = true
            return
        }
        session.isPresented = false
        closeHostSheet()
        try? await Task.sleep(for: .milliseconds(550))
        session.isPresented = true
    }

    // MARK: Progress

    @ViewBuilder private var progressTab: some View {
        let ordered = LiftMuscle.ordered.filter { (weekCounts[$0] ?? 0) > 0 }
        BroopSectionTitle(String(localized: "Sets per muscle")).padding(.top, 24)
        BroopCaps(String(localized: "Last 7 days · estimated"), size: 10, color: BroopPalette.textSecondary)
            .padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 12)
        VStack(alignment: .leading, spacing: 14) {
            if ordered.isEmpty {
                Text("Once you've logged a session, this shows how many sets each muscle got this week, against what the research associates with growth.")
                    .font(BroopType.regular(13.5)).foregroundStyle(BroopPalette.textBody)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(ordered, id: \.self) { muscleBar($0, sets: weekCounts[$0] ?? 0) }
                Text("Counted from the muscles you assigned each exercise: direct sets count once, indirect ones half. The tick is about 4 sets a week — below that, studies across GROUPS of people stop reliably detecting growth. It is a research reference, not a target for you, and above it gains continue with strongly diminishing returns and no clear ceiling, so the bar has no \"full\".")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(BroopPalette.card))

        BroopSectionTitle(String(localized: "Sessions")).padding(.top, 30).padding(.bottom, 12)
        if history.isEmpty {
            Text("Finished sessions land here, with every set you logged.")
                .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
        }
        LazyVStack(spacing: 8) {
            ForEach(history, id: \.id) { s in
                Button { viewing = SessionTarget(id: s.id, session: s) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 16)).foregroundStyle(.white)
                            .frame(width: 46, height: 36)
                            .background(RoundedRectangle(cornerRadius: 7).fill(BroopActivityPalette.strainBlue))
                        VStack(alignment: .leading, spacing: 3) {
                            BroopCaps(s.programName ?? String(localized: "Session"), size: 12).lineLimit(1)
                            Text(verbatim: Date(timeIntervalSince1970: TimeInterval(s.startTs)).formatted(date: .abbreviated, time: .shortened))
                                .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(BroopPalette.textSecondary)
                    }
                    .padding(8).padding(.trailing, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BroopPalette.row))
                }
                .buttonStyle(BroopPressableStyle())
            }
        }
    }

    /// One muscle's week, drawn as the screen draws it: the number is the truth, the bar spans 20
    /// sets purely as a drawing choice, and the ~4-set research floor is a tick, never a "done" point.
    private func muscleBar(_ muscle: LiftMuscle, sets: Double) -> some View {
        let floor = LiftMetrics.ReferenceDose.hypertrophyMinimumSetsPerWeek
        let fill = min(1.0, sets / 20)
        let tick = min(1.0, floor / 20)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                BroopCaps(muscle.displayName, size: 10.5, color: BroopPalette.textBody)
                Spacer()
                Text(verbatim: LiftFormat.trim(sets)).font(BroopType.number(16))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(BroopPalette.track)
                    Capsule().fill(BroopPalette.effort.opacity(sets >= floor ? 1 : 0.45)).frame(width: max(3, geo.size.width * fill))
                    Rectangle().fill(Color.white.opacity(0.6)).frame(width: 2).offset(x: max(0, geo.size.width * tick - 1))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        programs = (try? await store.liftPrograms(deviceId: repo.deviceId)) ?? []
        let now = Int(Date().timeIntervalSince1970)
        history = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: now - 180 * 86_400, toTs: now)) ?? [])
            .filter { $0.endTs != nil }
            .sorted { $0.startTs > $1.startTs }
        weekCounts = (try? await store.liftSetCounts(deviceId: repo.deviceId, fromTs: now - 7 * 86_400, toTs: now).fractional) ?? [:]
        loaded = true
    }
}
#endif
