#if os(iOS)
import SwiftUI
import StrandDesign

/// WHOOP's activity type picker: a search field, MOST RECENT, then every activity A to Z as a pictogram
/// and a tracked caps name. Built on the same `WorkoutCatalog` and `RecentSportsPrefs` the classic
/// browser uses. `allowsCustom` adds a "Use “…”" row so the Add / Edit sheet keeps its free-text sport.
struct BroopActivityTypePicker: View {
    var title: String = String(localized: "Choose activity")
    var subtitle: String? = nil
    var current: String? = nil
    var allowsCustom = false
    /// Record the pick as a recent selection (Start flow). Add / Edit record on save instead.
    var recordsRecent = true
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searching: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: [WorkoutCatalog.Sport] {
        WorkoutCatalog.matching(query).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var recents: [String] {
        RecentSportsPrefs.recent().filter { allowsCustom || WorkoutCatalog.sport(named: $0) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            BroopActivityHeader(title: title, subtitle: subtitle, leadingSymbol: "xmark", onBack: { dismiss() })
                .padding(.horizontal, BroopMetrics.page)
            searchField
                .padding(.horizontal, BroopMetrics.page)
                .padding(.top, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if allowsCustom, !trimmed.isEmpty, WorkoutCatalog.sport(named: trimmed) == nil {
                        row(trimmed, label: String(localized: "Use “\(trimmed)”"), symbol: "plus")
                    }
                    if trimmed.isEmpty, !recents.isEmpty {
                        BroopActivityDivider(title: String(localized: "Most recent"))
                            .padding(.top, 18).padding(.bottom, 6)
                        ForEach(recents, id: \.self) { row($0) }
                    }
                    BroopActivityDivider(title: trimmed.isEmpty ? String(localized: "All A-Z") : String(localized: "Results"))
                        .padding(.top, 18).padding(.bottom, 6)
                    if matches.isEmpty {
                        Text("No activities match. Try a different name.")
                            .font(BroopType.regular(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                            .padding(.vertical, 20)
                    }
                    ForEach(matches) { sport in row(sport.name, gps: sport.isDistanceSport) }
                }
                .padding(.horizontal, BroopMetrics.page)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(broopHex: 0x0B0E10).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(BroopPalette.textSecondary)
            TextField(String(localized: "Search"), text: $query)
                .font(BroopType.regular(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(BroopPalette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(broopHex: 0x2A2E33)))
    }

    private func row(_ name: String, label: String? = nil, symbol: String? = nil, gps: Bool = false) -> some View {
        let selected = current.map { $0.caseInsensitiveCompare(name) == .orderedSame } ?? false
        return Button {
            searching = false
            if recordsRecent { RecentSportsPrefs.recordSelection(name) }
            onPick(name)
            dismiss()
        } label: {
            HStack(spacing: 18) {
                Group {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        WorkoutTypeIcon(workoutType: name, size: 26, weight: .semibold, color: .white)
                    }
                }
                .frame(width: 36)
                BroopCaps(label ?? name, size: 13)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if gps {
                    BroopCaps(String(localized: "GPS"), size: 9, color: BroopPalette.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color(broopHex: 0x2A2E33) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BroopPressableStyle())
        .accessibilityLabel(Text(label ?? name))
    }
}
#endif
