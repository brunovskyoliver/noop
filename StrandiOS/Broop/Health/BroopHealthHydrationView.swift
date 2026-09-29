#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Broop Hydration (`.hydration`), rebuilt from the classic `HydrationView`: today's total against the
/// effort-adjusted goal as a thin ring, quick log (sip / cup / bottle / custom size), today's drinks with
/// edit and delete, water imported from Apple Health, and the last seven days. Every read and write goes
/// through the same Repository calls.
struct BroopHealthHydrationView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(HydrationStore.customSizeKey) private var customSizeML = HydrationGoal.cupML

    @State private var totalML: Double = 0
    @State private var history: [(day: String, value: Double)] = []
    @State private var entries: [HydrationEntry] = []
    @State private var importedML: Double = 0
    @State private var reloadTick = 0
    @State private var shown: Double = 0
    @State private var editing: HydrationEntry?
    @State private var editingCustom = false

    private static let water = Color(broopHex: 0x4FA8F0)
    private var goalML: Int { repo.hydrationGoalML(profileSex: profile.sex) }
    private var fraction: Double { HydrationGoal.fraction(totalML: totalML, goalML: goalML) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero.padding(.top, 14)
                quickLog.padding(.top, 28)
                drinks.padding(.top, BroopMetrics.section)
                week.padding(.top, BroopMetrics.section)
                BroopHealthFootnote(text: String(localized: "A simple goal that adjusts to your effort. General wellness guidance, not medical advice. Logged on \(Platform.deviceNounPhrase) only."))
                    .padding(.top, 20)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await reload() }
        .safeAreaInset(edge: .top, spacing: 0) { BroopHealthHeader(title: String(localized: "Hydration")) }
        .broopHealthScreen()
        .task(id: reloadTick) { await reload() }
        .onChange(of: fraction) { _, f in withAnimation(.easeOut(duration: 0.8)) { shown = f } }
        .sheet(item: $editing) { entry in
            BroopHealthAmountSheet(title: String(localized: "Edit drink"), initialML: entry.amountMl,
                                   onDelete: {
                                       editing = nil
                                       Task { _ = await repo.deleteHydrationEntry(id: entry.id); reloadTick &+= 1 }
                                   }) { ml in
                editing = nil
                Task { _ = await repo.updateHydrationEntry(id: entry.id, amountMl: ml); reloadTick &+= 1 }
            }
        }
        .sheet(isPresented: $editingCustom) {
            BroopHealthAmountSheet(title: String(localized: "Custom size"), initialML: customSizeML, onDelete: nil) { ml in
                customSizeML = ml
                editingCustom = false
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(BroopPalette.track, lineWidth: 8)
                Circle().trim(from: 0, to: shown)
                    .stroke(Self.water, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(verbatim: String(format: "%.1f", HydrationGoal.litres(fromML: totalML)))
                        .font(BroopType.number(54)).foregroundStyle(BroopPalette.textPrimary).broopNumeral(54)
                    BroopCaps(String(localized: "of \(String(format: "%.1f", HydrationGoal.litres(fromML: Double(goalML)))) L"),
                              size: 12, color: BroopPalette.textSecondary)
                }
            }
            .frame(width: 200, height: 200)
            BroopCaps(String(localized: "\(min(100, Int((fraction * 100).rounded(.towardZero))))% of today's goal"),
                      size: 11, color: BroopPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hydration today"))
        .accessibilityValue(Text(verbatim: "\(String(format: "%.1f", HydrationGoal.litres(fromML: totalML))) / \(String(format: "%.1f", HydrationGoal.litres(fromML: Double(goalML)))) L"))
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { shown = fraction } }
    }

    // MARK: Quick log

    private var quickLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            BroopCaps(String(localized: "Log a drink"), size: 12.5)
            HStack(spacing: 10) {
                logTile(String(localized: "Sip"), "drop", HydrationGoal.sipML)
                logTile(String(localized: "Cup"), "cup.and.saucer", HydrationGoal.cupML)
                logTile(String(localized: "Bottle"), "waterbottle", HydrationGoal.bottleML)
            }
            HStack(spacing: 10) {
                Button { Task { await add(customSizeML) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "drop.circle").font(.system(size: 18, weight: .light))
                            .foregroundStyle(BroopPalette.textSecondary)
                        BroopCaps(String(localized: "Custom \(customSizeML) ml"), size: 11.5)
                        Spacer()
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(BroopPalette.textPrimary)
                    }
                    .padding(.horizontal, 16).frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Log custom \(customSizeML) millilitres"))
                Button { editingCustom = true } label: {
                    Image(systemName: "pencil").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BroopPalette.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
                }
                .buttonStyle(BroopPressableStyle())
                .accessibilityLabel(Text("Set custom container size"))
            }
        }
    }

    private func logTile(_ title: String, _ symbol: String, _ ml: Int) -> some View {
        Button { Task { await add(ml) } } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Self.water)
                BroopCaps(title, size: 11)
                Text(verbatim: "\(ml) ml").font(BroopType.number(13)).foregroundStyle(BroopPalette.textSecondary)
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BroopPalette.card))
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Log")) \(title), \(ml) ml"))
    }

    // MARK: Today's drinks

    @ViewBuilder private var drinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BroopCaps(String(localized: "Today's drinks"), size: 12.5)
                Spacer()
                Text(verbatim: "\(Int(totalML)) ml").font(BroopType.number(16)).foregroundStyle(BroopPalette.textPrimary)
            }
            if entries.isEmpty && importedML <= 0 {
                BroopHealthCard {
                    Text("No drinks logged yet. Tap Sip, Cup or Bottle to start.")
                        .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    if importedML > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.text.square").foregroundStyle(BroopPalette.textSecondary)
                            Text("From Apple Health").font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                            Spacer()
                            Text(verbatim: "\(Int(importedML.rounded())) ml").font(BroopType.number(16)).foregroundStyle(BroopPalette.textPrimary)
                        }
                        .padding(.vertical, 13)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text("\(Int(importedML.rounded())) millilitres from Apple Health. Edit it in the app that logged it."))
                        if !entries.isEmpty { BroopHairline() }
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                        HStack(spacing: 12) {
                            Button { editing = e } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "drop.fill").font(.system(size: 13)).foregroundStyle(Self.water)
                                    Text(verbatim: AppClock.hourMinuteFormatter().string(from: e.loggedAt))
                                        .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textBody)
                                    Spacer()
                                    Text(verbatim: "\(e.amountMl) ml").font(BroopType.number(16)).foregroundStyle(BroopPalette.textPrimary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(BroopPressableStyle())
                            .accessibilityHint(Text("Tap to edit the amount"))
                            Button(role: .destructive) {
                                Task { _ = await repo.deleteHydrationEntry(id: e.id); reloadTick &+= 1 }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(BroopPalette.textSecondary)
                                    .frame(width: 34, height: 34).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Delete the \(e.amountMl) millilitre drink"))
                        }
                        .padding(.vertical, 6)
                        if i < entries.count - 1 { BroopHairline() }
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
                if !entries.isEmpty {
                    BroopHealthFootnote(text: String(localized: "Tap a drink to edit it, or use the trash to delete."))
                }
            }
        }
    }

    // MARK: Week

    private var week: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopCaps(String(localized: "Last 7 days"), size: 12.5)
            if history.isEmpty {
                Text("No history yet.").font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
            } else {
                let ceiling = max(Double(max(goalML, 1)), history.map(\.value).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(history.enumerated()), id: \.element.day) { i, bar in
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(BroopPalette.track).frame(height: 110)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(i == history.count - 1 ? Self.water : Self.water.opacity(0.5))
                                    .frame(height: max(bar.value > 0 ? 3 : 0, 110 * CGFloat(min(1, bar.value / ceiling))))
                            }
                            Text(verbatim: BroopHealthFormat.date(bar.day).map { $0.formatted(.dateTime.weekday(.narrow)) } ?? "·")
                                .font(BroopType.medium(12)).foregroundStyle(BroopPalette.textSecondary)
                                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: "\(bar.day): \(String(format: "%.1f", HydrationGoal.litres(fromML: bar.value))) L"))
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(BroopPalette.card))
    }

    // MARK: Data

    private func add(_ ml: Int) async {
        guard ml > 0 else { return }
        _ = await repo.logHydration(amountMl: ml)
        reloadTick &+= 1
    }

    private func reload() async {
        totalML = await repo.hydrationTotal(day: Repository.localDayKey(Date()))
        history = await repo.hydrationHistory(days: 7)
        entries = repo.hydrationEntries()
        importedML = await repo.hydrationImportedTotal(day: Repository.localDayKey(Date()))
    }
}

/// Amount editor for a drink or the custom container: a big figure with − / + (10 ml steps, 10 ml – 3 L).
struct BroopHealthAmountSheet: View {
    let title: String
    let initialML: Int
    let onDelete: (() -> Void)?
    let onSave: (Int) -> Void
    @State private var ml: Int = 0
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialML: Int, onDelete: (() -> Void)?, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.initialML = initialML
        self.onDelete = onDelete
        self.onSave = onSave
        _ml = State(initialValue: initialML)
    }

    var body: some View {
        VStack(spacing: 24) {
            BroopCaps(title, size: 13).padding(.top, 22)
            HStack(spacing: 28) {
                step("minus", -10)
                Text(verbatim: "\(ml) ml").font(BroopType.number(42)).foregroundStyle(BroopPalette.textPrimary)
                    .frame(minWidth: 150)
                step("plus", 10)
            }
            HStack(spacing: 12) {
                BroopHealthButton(title: String(localized: "Cancel"), kind: .secondary) { dismiss() }
                BroopHealthButton(title: String(localized: "Save")) { onSave(min(3000, max(10, ml))) }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    BroopCaps(String(localized: "Delete drink"), size: 11.5, color: BroopPalette.bandLow)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BroopMetrics.page)
        .frame(maxWidth: .infinity)
        .background(BroopPalette.bgMid.ignoresSafeArea())
        .presentationDetents([.height(onDelete == nil ? 280 : 320)])
        .preferredColorScheme(.dark)
    }

    private func step(_ symbol: String, _ delta: Int) -> some View {
        Button { ml = min(3000, max(10, ml + delta)) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 48, height: 48).background(Circle().fill(BroopPalette.card))
        }
        .buttonStyle(BroopPressableStyle())
        .buttonRepeatBehavior(.enabled)
    }
}
#endif
