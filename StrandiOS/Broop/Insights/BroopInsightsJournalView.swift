#if os(iOS)
import SwiftUI
import WhoopStore

// The Broop Journal: WHOOP's daily question list (date strip, "What happened on …?", ✕ / ✓ answer squares,
// blue quantity capsules, CUSTOMIZE JOURNAL sheet) over NOOP's native journal. Every read and write goes
// through the same Repository calls the classic `JournalLogCard` uses, under the native journal source, so
// imported history is never touched and a logged day lines up with a WHOOP export.

/// The selected day's answers plus the catalog inputs. Loads off the view body, one day at a time.
@MainActor
final class BroopInsightsJournalModel: ObservableObject {
    @Published private(set) var importedQuestions: [String] = []
    @Published private(set) var answers: [String: Bool] = [:]
    @Published private(set) var numeric: [String: Double] = [:]
    /// Days (local day keys) that carry at least one native answer: the strip's check marks.
    @Published private(set) var filledDays: Set<String> = []
    @Published private(set) var loaded = false
    private var importedLoaded = false

    static func dayKey(offset: Int, now: Date = Date()) -> String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now)
    }

    func load(repo: Repository, offset: Int) async {
        if !importedLoaded {
            let imported = await repo.importedJournalEntries()
            importedQuestions = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
            importedLoaded = true
        }
        let key = Self.dayKey(offset: offset)
        answers = await repo.nativeJournalAnswers(day: key)
        numeric = await repo.nativeJournalNumeric(day: key)
        let oldest = Self.dayKey(offset: BroopInsightsJournalView.dayOffsets.max() ?? 6)
        let newest = Self.dayKey(offset: BroopInsightsJournalView.dayOffsets.min() ?? -1)
        filledDays = await repo.nativeJournalDays(from: oldest, to: newest)
        loaded = true
    }
}

struct BroopInsightsJournalView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = JournalCatalogStore()
    @StateObject private var model = BroopInsightsJournalModel()

    /// -1 = tomorrow, 0 = today, 1 = yesterday … 6 days ago. The same bounded window as the classic card
    /// (#656): journal answers feed the effect engine, so unbounded backfill would distort it.
    @State private var dayOffset = 0
    @State private var currentDayKey = Repository.localDayKey(Date())
    @State private var showCustomize = false
    @State private var showVoiceJournal = false
    @EnvironmentObject private var coach: AICoachEngine
    /// Numeric answer being edited (drives the entry alert).
    @State private var editingNumeric: JournalCatalogItem?
    @State private var numericDraft = ""
    /// Collapsed groups, shared with the classic card's key so both surfaces agree.
    @AppStorage("journal.collapsedGroups") private var collapsedGroupsRaw = ""

    static let dayOffsets: [Int] = Array((-1...6).reversed())

    private var dayKey: String { BroopInsightsJournalModel.dayKey(offset: dayOffset) }

    private var visibleItems: [JournalCatalogItem] {
        catalog.resolvedItems(imported: model.importedQuestions, includeHidden: false)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                dateRow.padding(.top, 6)
                dayStrip.padding(.top, 14)
                headline.padding(.top, 22)
                if !model.loaded {
                    ProgressView().tint(BroopPalette.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else if visibleItems.isEmpty {
                    BroopInsightsNote(symbol: "square.and.pencil", title: String(localized: "No behaviours tracked"),
                                      text: String(localized: "Tap the pencil to choose which behaviours your journal asks about, or add your own."))
                        .padding(.top, 24)
                } else {
                    ForEach(JournalGroup.displayOrder, id: \.self) { group in
                        groupSection(group)
                    }
                }
                moreSection.padding(.top, 36)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Answers save as they are tapped; the sticky button closes the journal, WHOOP-style.
            BroopInsightsPrimaryButton(title: String(localized: "Done")) { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(colors: [BroopPalette.bgBottom.opacity(0), BroopPalette.bgBottom],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                        .ignoresSafeArea()
                )
        }
        .background(BroopInsightsJournalBackground())
        .broopInsightsChrome(String(localized: "Journal"), fill: BroopInsightsJournalBackground.topColor) {
            HStack(spacing: 0) {
                if coach.canUseJournalByVoice {
                    BroopNavIcon(symbol: "mic", label: String(localized: "Log your day by voice")) { showVoiceJournal = true }
                }
                BroopNavIcon(symbol: "pencil", label: String(localized: "Customize journal")) { showCustomize = true }
            }
        }
        .sheet(isPresented: $showVoiceJournal) {
            BroopInsightsVoiceJournalSheet(day: Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()) {
                Task { await model.load(repo: repo, offset: dayOffset) }
            }
            .environmentObject(coach)
            .environmentObject(repo)
        }
        .sheet(isPresented: $showCustomize) {
            BroopInsightsJournalCustomizeSheet(catalog: catalog, importedQuestions: model.importedQuestions)
        }
        .alert(editingNumeric?.display ?? "", isPresented: numericAlertBinding) {
            TextField(String(localized: "Amount"), text: $numericDraft).keyboardType(.decimalPad)
            Button(String(localized: "Save")) { commitNumericDraft() }
            if let item = editingNumeric, model.numeric[item.canonical] != nil {
                Button(String(localized: "Clear"), role: .destructive) { clear(item.canonical) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            if let unit = editingNumeric?.kind.unitLabel, !unit.isEmpty {
                Text(verbatim: unit)
            }
        }
        .task(id: "\(repo.refreshSeq)|\(currentDayKey)|\(dayOffset)") {
            await model.load(repo: repo, offset: dayOffset)
        }
        .onAppear {
            refreshDayKey()
            // #656: a day the Today journal widget deep-linked to. Consumed once.
            if let day = router.pendingJournalDayOffset {
                dayOffset = min(max(day, -1), 6)
                router.pendingJournalDayOffset = nil
            }
        }
        .task {
            // The evening-review reminder's tap: journal by voice for today, once the model is known ready.
            await coach.refreshAppleAvailability()
            if router.pendingVoiceJournal {
                router.pendingVoiceJournal = false
                if coach.canUseJournalByVoice { showVoiceJournal = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDayKey() } }
    }

    private func refreshDayKey() {
        let key = Repository.localDayKey(Date())
        if key != currentDayKey { currentDayKey = key }
    }

    // MARK: Date header

    private var selectedDate: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
    }

    private var dateRow: some View {
        HStack(spacing: 10) {
            Button { step(1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                    .frame(width: 30, height: 32, alignment: .leading)
            }
            .disabled(dayOffset >= 6).opacity(dayOffset >= 6 ? 0.3 : 1)
            .accessibilityLabel(Text("Previous day"))
            // Tapping the day returns to today, as the date capsule does elsewhere in Broop.
            Button { withAnimation(.snappy) { dayOffset = 0 } } label: {
                BroopCaps(dayLabel, size: 11.5).lineLimit(1)
            }
            .accessibilityHint(Text("Returns to today"))
            Button { step(-1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .bold))
                    .frame(width: 30, height: 32)
            }
            .disabled(dayOffset <= -1).opacity(dayOffset <= -1 ? 0.3 : 1)
            .accessibilityLabel(Text("Next day"))
            Spacer(minLength: 8)
            NavigationLink {
                BroopInsightsImpactView()
            } label: {
                BroopInsightsPill(title: String(localized: "Insights"), symbol: "lightbulb",
                                  fill: Color.white.opacity(0.12))
            }
        }
        .foregroundStyle(BroopPalette.textPrimary)
        .buttonStyle(.plain)
    }

    private var dayLabel: String {
        switch dayOffset {
        case 0: return String(localized: "Today")
        case -1: return String(localized: "Tomorrow")
        default: return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    private func step(_ by: Int) {
        withAnimation(.snappy) { dayOffset = min(max(dayOffset + by, -1), 6) }
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.dayOffsets, id: \.self) { off in
                        dayCapsule(off).id(off)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .onAppear { DispatchQueue.main.async { proxy.scrollTo(dayOffset, anchor: .center) } }
            .onChange(of: dayOffset) { _, off in withAnimation { proxy.scrollTo(off, anchor: .center) } }
        }
    }

    private func dayCapsule(_ offset: Int) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        let key = BroopInsightsJournalModel.dayKey(offset: offset)
        let selected = offset == dayOffset
        let filled = model.filledDays.contains(key)
        return Button { withAnimation(.snappy) { dayOffset = offset } } label: {
            VStack(spacing: 7) {
                Text(verbatim: date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(BroopType.medium(12.5))
                    .foregroundStyle(BroopPalette.textPrimary.opacity(0.85))
                Text(verbatim: date.formatted(.dateTime.day()))
                    .font(BroopType.number(19))
                    .foregroundStyle(BroopPalette.textPrimary)
                ZStack {
                    if filled {
                        Circle().fill(Color(broopHex: 0x5FE3A0))
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black.opacity(0.75))
                    } else {
                        Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.3)
                    }
                }
                .frame(width: 17, height: 17)
            }
            .frame(width: 50, height: 88)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.22 : 0.10)))
            .overlay { if selected { Capsule().strokeBorder(Color.white, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: date.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(Text(filled ? "Journal filled out" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: headlineText)
                .font(BroopType.demi(24))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            BroopInsightsBody(text: dayOffset == -1
                ? String(localized: "Logging ahead for tomorrow: today's activities inform tomorrow's recovery, just as yesterday's are reflected in today's. Tomorrow's answers line up with tomorrow's morning.")
                : String(localized: "Answers are about the night and day leading into this morning, the same attribution a WHOOP export uses, so logged and imported days line up."),
                size: 12.5, color: BroopPalette.textSecondary)
        }
    }

    private var headlineText: String {
        let monthDay = selectedDate.formatted(.dateTime.month(.wide).day())
        switch dayOffset {
        case -1: return String(localized: "What's planned for tomorrow, \(monthDay)?")
        case 0: return String(localized: "What's happening today, \(monthDay)?")
        case 1: return String(localized: "What happened yesterday, \(monthDay)?")
        default:
            let wd = selectedDate.formatted(.dateTime.weekday(.abbreviated))
            return String(localized: "What happened on \(wd), \(monthDay)?")
        }
    }

    // MARK: Questions

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }

    private func toggleCollapsed(_ group: JournalGroup) {
        var set = collapsedGroups
        if set.contains(group.rawValue) { set.remove(group.rawValue) } else { set.insert(group.rawValue) }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }

    @ViewBuilder private func groupSection(_ group: JournalGroup) -> some View {
        let items = visibleItems.filter { $0.group == group }
            .sorted { ($0.sortIndex, $0.display) < ($1.sortIndex, $1.display) }
        if !items.isEmpty {
            let collapsed = collapsedGroups.contains(group.rawValue)
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy) { toggleCollapsed(group) } } label: {
                    HStack(spacing: 10) {
                        BroopInsightsSectionRule(title: group.title, trailing: "\(items.count)")
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(group.title), \(items.count) items, \(collapsed ? "collapsed" : "expanded")"))
                if !collapsed {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        questionRow(item)
                        if index < items.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.top, 30)
        }
    }

    @ViewBuilder private func questionRow(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: item.display)
                .font(BroopType.medium(17.5))
                .foregroundStyle(BroopPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.kind.isNumeric {
                numericControl(item)
            } else {
                answerSquare(item, yes: false)
                answerSquare(item, yes: true)
            }
        }
        .padding(.vertical, 15)
    }

    private func answerSquare(_ item: JournalCatalogItem, yes: Bool) -> some View {
        let selected = model.answers[item.canonical] == yes
        let fill: Color = selected ? (yes ? BroopInsightsPalette.answerBlue : Color.white) : BroopInsightsPalette.answerIdle
        let glyph: Color = selected ? Color.black.opacity(0.85) : BroopPalette.textPrimary
        return Button {
            Task {
                // Tri-state: tapping the selected answer again clears it (native rows only).
                if selected {
                    await repo.clearJournalAnswer(day: dayKey, question: item.canonical)
                } else {
                    await repo.saveJournalAnswer(day: dayKey, question: item.canonical, answeredYes: yes)
                }
                await model.load(repo: repo, offset: dayOffset)
            }
        } label: {
            Image(systemName: yes ? "checkmark" : "xmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(glyph)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(Text(yes ? "Yes" : "No"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func numericControl(_ item: JournalCatalogItem) -> some View {
        let current = model.numeric[item.canonical]
        let unit = item.kind.unitLabel ?? ""
        return HStack(spacing: 8) {
            stepButton("minus", item: item, current: current)
            Button {
                numericDraft = current.map(Self.format) ?? ""
                editingNumeric = item
            } label: {
                Text(verbatim: current.map { Self.format($0) + (unit.isEmpty ? "" : " \(unit)") } ?? "—")
                    .font(BroopType.demi(15.5))
                    .foregroundStyle(current == nil ? BroopPalette.textPrimary : Color.black.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 58, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(current == nil ? BroopInsightsPalette.answerIdle : BroopInsightsPalette.answerBlue))
            }
            .buttonStyle(BroopPressableStyle())
            .accessibilityLabel(Text("\(item.display), \(current.map(Self.format) ?? "no value")"))
            stepButton("plus", item: item, current: current)
        }
    }

    private func stepButton(_ symbol: String, item: JournalCatalogItem, current: Double?) -> some View {
        Button {
            let base = current ?? 0
            commitNumeric(item.canonical, value: max(0, symbol == "plus" ? base + 1 : base - 1))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 28, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(symbol == "plus" ? "Increase" : "Decrease"))
    }

    private var numericAlertBinding: Binding<Bool> {
        Binding(get: { editingNumeric != nil }, set: { if !$0 { editingNumeric = nil } })
    }

    private func commitNumericDraft() {
        guard let item = editingNumeric else { return }
        let cleaned = numericDraft.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned) { commitNumeric(item.canonical, value: v) }
    }

    private func commitNumeric(_ q: String, value: Double) {
        Task {
            await repo.saveJournalNumeric(day: dayKey, question: q, value: value)
            await model.load(repo: repo, offset: dayOffset)
        }
    }

    private func clear(_ q: String) {
        Task {
            await repo.clearJournalAnswer(day: dayKey, question: q)
            await model.load(repo: repo, offset: dayOffset)
        }
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: More logging

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            BroopInsightsSectionRule(title: String(localized: "More to log"))
                .padding(.bottom, 4)
            NavigationLink {
                BroopFinalACaffeinePage()
            } label: {
                BroopInsightsLinkRow(symbol: "cup.and.saucer", title: String(localized: "Caffeine"),
                                     detail: String(localized: "Log an intake and see a rough estimate of what may still be active."))
            }
            .buttonStyle(.plain)
            NavigationLink {
                BroopFinalAMoodPage()
            } label: {
                BroopInsightsLinkRow(symbol: "face.smiling", title: String(localized: "Mood check-in"),
                                     detail: String(localized: "How you feel today, and how mood lines up with your body."))
            }
            .buttonStyle(.plain)
            NavigationLink(value: BroopScreen.insightsHub) {
                BroopInsightsLinkRow(symbol: "wand.and.sparkles", title: String(localized: "What moves you"),
                                     detail: String(localized: "Ranked, lag-aware: which habits move your Charge, plus your alcohol and caffeine dose-response."))
            }
            .buttonStyle(.plain)
        }
    }
}

/// The Journal canvas: a coloured wash at the top fading to the page black. Sand in the morning and
/// daytime, violet in the evening, as the WHOOP journal does.
struct BroopInsightsJournalBackground: View {
    private static var evening: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 17 || hour < 4
    }
    /// The gradient's top colour, which the pinned header fills with.
    static var topColor: Color { evening ? Color(broopHex: 0x3F2F7A) : Color(broopHex: 0x8F7D66) }

    var body: some View {
        let evening = Self.evening
        let top = Self.topColor
        let mid = evening ? Color(broopHex: 0x241F44) : Color(broopHex: 0x3C4650)
        LinearGradient(stops: [
            .init(color: top, location: 0),
            .init(color: mid, location: 0.28),
            .init(color: BroopPalette.bgBottom, location: 0.62),
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}

// MARK: - Customize

/// CUSTOMIZE JOURNAL: category tabs, every behaviour with a checkbox (tracked or hidden), custom items with
/// rename / regroup / retype / delete, and an "add your own" field. All edits go through `JournalCatalogStore`,
/// the classic card's store, so the stored key never changes on a rename and history stays joined.
struct BroopInsightsJournalCustomizeSheet: View {
    @ObservedObject var catalog: JournalCatalogStore
    let importedQuestions: [String]
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case all, group(JournalGroup) }
    @State private var tab: Tab = .all
    @State private var search = ""
    @State private var draft = ""
    @State private var draftNumeric = false
    @State private var draftGroup: JournalGroup = .other
    @State private var renaming: JournalCatalogItem?
    @State private var renameDraft = ""
    @State private var deleting: JournalCatalogItem?

    private var items: [JournalCatalogItem] {
        let all = catalog.resolvedItems(imported: importedQuestions, includeHidden: true)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { item in
            if case .group(let g) = tab, item.group != g { return false }
            return q.isEmpty || item.display.lowercased().contains(q)
        }
        .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabs.padding(.top, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        TextField(String(localized: "Search for behaviours"), text: $search)
                            .broopInsightsField()
                            .padding(.bottom, 16)
                        addCard.padding(.bottom, 18)
                        ForEach(items) { item in
                            row(item)
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                        BroopInsightsBody(text: String(localized: "Renaming keeps the original question behind the scenes, so a WHOOP import still lines up. Custom items are deleted; built-in ones are hidden and can be ticked again later."),
                                          size: 12, color: BroopPalette.textTertiary)
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, BroopMetrics.page)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .background(BroopBackground())
            .broopInsightsChrome(String(localized: "Customize journal"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                    }
                    .accessibilityLabel(Text("Done"))
                }
            }
            .alert(String(localized: "Rename item"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(String(localized: "Display name"), text: $renameDraft)
                Button(String(localized: "Save")) {
                    if let item = renaming { catalog.rename(item.canonical, to: renameDraft) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("History stays under the original question so WHOOP imports still line up.")
            }
            .confirmationDialog(String(localized: "Delete this custom item?"),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let item = deleting { catalog.remove(item.canonical) }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Logged answers stay in your history.")
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                tabButton(.all, String(localized: "All"))
                ForEach(JournalGroup.displayOrder, id: \.self) { g in tabButton(.group(g), g.title) }
            }
            .padding(.horizontal, BroopMetrics.page)
        }
    }

    private func tabButton(_ t: Tab, _ title: String) -> some View {
        let on = tab == t
        return Button { withAnimation(.snappy) { tab = t } } label: {
            VStack(spacing: 7) {
                BroopCaps(title, size: 11, color: on ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                Rectangle().fill(on ? Color.white : .clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var addCard: some View {
        BroopInsightsCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                BroopCaps(String(localized: "Add your own"), size: 10.5, color: BroopPalette.textSecondary)
                TextField(String(localized: "Add a custom item…"), text: $draft)
                    .broopInsightsField()
                HStack(spacing: 10) {
                    Menu {
                        Button(String(localized: "Yes/No")) { draftNumeric = false }
                        Button(String(localized: "Number")) { draftNumeric = true }
                    } label: {
                        BroopInsightsPill(title: draftNumeric ? String(localized: "Number") : String(localized: "Yes/No"), symbol: "chevron.down")
                    }
                    Menu {
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in
                            Button(g.title) { draftGroup = g }
                        }
                    } label: {
                        BroopInsightsPill(title: draftGroup.title, symbol: "folder")
                    }
                    Spacer()
                    Button {
                        let t = draft.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        catalog.addCustom(t, kind: draftNumeric ? .numeric(unitLabel: nil) : .bool, group: draftGroup)
                        draft = ""
                    } label: {
                        BroopCaps(String(localized: "Add"), size: 11, color: .black)
                            .padding(.horizontal, 16).frame(height: 30)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
            }
        }
    }

    private func row(_ item: JournalCatalogItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.display)
                    .font(BroopType.medium(16))
                    .foregroundStyle(BroopPalette.textPrimary)
                Text(verbatim: subtitle(item))
                    .font(BroopType.regular(12.5))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(String(localized: "Rename…")) { renameDraft = item.displayName ?? item.canonical; renaming = item }
                Menu(String(localized: "Group")) {
                    ForEach(JournalGroup.displayOrder, id: \.self) { g in
                        Button(g.title) { catalog.setGroup(item.canonical, to: g) }
                    }
                }
                if item.kind.isNumeric {
                    Button(String(localized: "Change to Yes/No")) { catalog.setKind(item.canonical, to: .bool) }
                } else {
                    Button(String(localized: "Change to Number")) { catalog.setKind(item.canonical, to: .numeric(unitLabel: nil)) }
                }
                if item.custom {
                    Button(String(localized: "Delete"), role: .destructive) { deleting = item }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BroopPalette.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text("Edit \(item.display)"))
            checkbox(item)
        }
        .padding(.vertical, 12)
    }

    private func subtitle(_ item: JournalCatalogItem) -> String {
        var parts = [item.group.title, item.kind.isNumeric ? String(localized: "Number") : String(localized: "Yes/No")]
        if item.custom { parts.append(String(localized: "Custom")) }
        if item.displayName != nil { parts.append(item.canonical) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func checkbox(_ item: JournalCatalogItem) -> some View {
        let on = !item.hidden
        Button {
            if on {
                // A custom item has no hidden state: unticking it deletes it, so ask first.
                if item.custom { deleting = item } else { catalog.remove(item.canonical) }
            } else {
                catalog.restore(item.canonical)
            }
        } label: {
            ZStack {
                if on {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(BroopInsightsPalette.answerBlue)
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.black.opacity(0.85))
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white, lineWidth: 2)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.display))
        .accessibilityValue(Text(on ? "Tracked" : "Not tracked"))
    }
}
#endif
