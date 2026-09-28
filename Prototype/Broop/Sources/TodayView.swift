import SwiftUI

/// Home. Spacing and sizes follow a native WHOOP screenshot measured at 375 pt wide.
struct TodayView: View {
    @EnvironmentObject var store: SampleStore
    @Binding var tab: AppTab
    @State private var path: [Route] = []
    @State private var showCoach = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    header.padding(.top, 6)
                    Wordmark().padding(.top, 26)
                    dials.padding(.top, 20)
                    monitors.padding(.top, 26)
                    SectionTitle("My Day").padding(.top, 32).padding(.horizontal, 4)
                    coachRow.padding(.top, 16)
                    activities.padding(.top, 20)
                    SectionTitle(text: "My Dashboard") {
                        Button {} label: { Caps("Edit", size: 10, color: Broop.Palette.textSecondary) }
                    }
                    .padding(.top, 36)
                    .padding(.horizontal, 4)
                    dashboard.padding(.top, 16)
                }
                .padding(.horizontal, Broop.Space.page)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
            .statusBarScrim()
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .score(let kind): ScoreDetailView(initial: kind)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if path.isEmpty { QuickActionsButton().padding(.trailing, 16).padding(.bottom, 12) }
        }
        .sheet(isPresented: $showCoach) { CoachSheet().environmentObject(store) }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            DateNavigator()
            HStack {
                Button { tab = .more } label: { Avatar() }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Profile")
                    .padding(.leading, 4)
                Spacer()
                StrapStatus(level: store.battery)
            }
        }
    }

    // MARK: Dials

    private var dials: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ScoreKind.allCases) { kind in
                Button { path.append(.score(kind)) } label: {
                    VStack(spacing: 11) {
                        ScoreDial(
                            kind: kind,
                            value: kind.value(store.selected),
                            marker: kind == .effort ? store.readiness.target.lowerBound : nil
                        )
                        HStack(spacing: 4) {
                            Caps(kind.title)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Broop.Palette.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Monitors

    private var monitors: some View {
        let outliers = store.outliers
        let total = store.vitals.count
        let ok = outliers.isEmpty
        let stress = store.stress
        return HStack(spacing: 10) {
            Button { tab = .health } label: {
                MonitorTile(
                    title: ["Health", "Monitor"],
                    status: ok ? ["Within", "Range"] : ["Outside", "Range"],
                    statusColor: ok ? Broop.Palette.teal : Broop.Palette.warning,
                    detail: "\(total - outliers.count)/\(total) Metrics"
                ) {
                    Image(systemName: ok ? "checkmark" : "exclamationmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(ok ? Broop.Palette.teal : Broop.Palette.warning)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 4).fill((ok ? Broop.Palette.teal : Broop.Palette.warning).opacity(0.22)))
                }
            }
            .buttonStyle(PressableStyle())

            Button { tab = .health } label: {
                MonitorTile(
                    title: ["Stress", "Monitor"],
                    status: [stress.label],
                    statusColor: stress.color,
                    detail: Fmt.time(stress.time)
                ) {
                    Text(Fmt.one(stress.value))
                        .font(Broop.Typeface.number(13.5))
                        .numeral(13.5, color: stress.color)
                        .foregroundStyle(stress.color)
                        .frame(width: 25, height: 24)
                        .background(RoundedRectangle(cornerRadius: 4).fill(stress.color.opacity(0.22)))
                }
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: My Day

    private var coachRow: some View {
        HStack(spacing: 13) {
            Button { showCoach = true } label: {
                BrandBadge(size: 28, gradientRing: true)
                    .frame(width: 47, height: 46)
                    .background(RoundedRectangle(cornerRadius: Broop.Radius.card, style: .continuous).fill(Broop.Palette.card))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Coach")

            Button { showCoach = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sunrise")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Broop.Palette.textSecondary)
                    Text("Daily Outlook")
                        .font(Broop.Typeface.medium(14))
                        .foregroundStyle(Broop.Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Broop.Palette.textSecondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: Broop.Radius.card, style: .continuous).fill(Broop.Palette.card))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var activities: some View {
        let day = store.selected
        return Card(padding: 12) {
            VStack(spacing: 12) {
                HStack {
                    Caps("Today's Activities", size: 11)
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Broop.Palette.textSecondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 2)

                Button { path.append(.score(.rest)) } label: {
                    ActivityTile(
                        symbol: "moon.fill", value: Fmt.duration(day.asleepMinutes), color: Broop.Palette.rest,
                        name: "Sleep", start: day.bedtime, end: day.wake
                    )
                }
                .buttonStyle(PressableStyle())

                ForEach(day.activities) { activity in
                    Button { path.append(.score(.effort)) } label: {
                        ActivityTile(activity: activity)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: Dashboard

    private var dashboard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(store.dashboard.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 { Hairline() }
                    Button { path.append(.score(metric.home)) } label: {
                        DashboardRow(metric: metric)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Tiles

/// Half-width tile: stacked caps title with a chevron, then a status badge beside tight status lines.
struct MonitorTile<Badge: View>: View {
    let title: [String]
    let status: [String]
    let statusColor: Color
    let detail: String
    @ViewBuilder var badge: Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                lines(title, color: Broop.Palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Broop.Palette.textSecondary)
                    .offset(y: 1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .center, spacing: 10) {
                badge
                VStack(alignment: .leading, spacing: 0) {
                    lines(status, color: statusColor)
                    Text(detail)
                        .font(Broop.Typeface.demi(12.5))
                        .foregroundStyle(Broop.Palette.textBody)
                        .frame(height: 15, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Broop.Radius.card, style: .continuous).fill(Broop.Palette.tile))
    }

    /// Caps lines on a fixed 14 pt pitch; Avenir's default leading is looser than WHOOP's.
    private func lines(_ text: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(text, id: \.self) { Caps($0, color: color).frame(height: 14, alignment: .leading) }
        }
    }
}

/// Solid colour badge (icon + value), uppercase name, start/end times and a timeline tick.
struct ActivityTile: View {
    let symbol: String
    let value: String
    let color: Color
    let name: String
    let start: Date
    let end: Date

    init(symbol: String, value: String, color: Color, name: String, start: Date, end: Date) {
        self.symbol = symbol
        self.value = value
        self.color = color
        self.name = name
        self.start = start
        self.end = end
    }

    init(activity: Activity) {
        self.init(
            symbol: activity.symbol, value: Fmt.one(activity.effort), color: Broop.Palette.effort,
            name: activity.name, start: activity.start,
            end: activity.start.addingTimeInterval(Double(activity.minutes) * 60)
        )
    }

    var body: some View {
        HStack(spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(value).font(Broop.Typeface.number(17)).numeral(17)
            }
            .foregroundStyle(Broop.Palette.textPrimary)
            .frame(width: 94, height: 36)
            .background(RoundedRectangle(cornerRadius: Broop.Radius.badge, style: .continuous).fill(color))

            Caps(name, size: 12).lineLimit(2)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.time(start))
                Text(Fmt.time(end))
            }
            .font(Broop.Typeface.demi(12))
            .foregroundStyle(Broop.Palette.textBody)
            VStack(spacing: 0) {
                Circle().fill(Broop.Palette.textPrimary).frame(width: 2.5, height: 2.5)
                Rectangle().fill(color).frame(width: 2)
                Circle().fill(Broop.Palette.textPrimary).frame(width: 2.5, height: 2.5)
            }
            .frame(height: 28)
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Broop.Radius.row, style: .continuous).fill(Broop.Palette.row))
    }
}

struct DashboardRow: View {
    let metric: Contributor

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(metric.name, size: 10, color: Broop.Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(metric.text).font(Broop.Typeface.number(20)).numeral(20)
                    if !metric.unit.isEmpty {
                        Caps(metric.unit, size: 9, color: Broop.Palette.textSecondary)
                    }
                }
                .foregroundStyle(Broop.Palette.textPrimary)
            }
            Spacer()
            DeltaPill(contributor: metric)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Broop.Palette.textTertiary)
        }
        .padding(.vertical, 11)
    }
}

/// White floating "+" (start activity, live HR, journal, breathe).
struct QuickActionsButton: View {
    var body: some View {
        Menu {
            Button("Start activity", systemImage: "figure.run") {}
            Button("Live heart rate", systemImage: "heart") {}
            Button("Log journal", systemImage: "book.closed") {}
            Button("Breathe", systemImage: "wind") {}
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.black)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .accessibilityLabel("Quick actions")
    }
}

struct CoachSheet: View {
    @EnvironmentObject var store: SampleStore
    private let prompts = ["Why is my Charge lower today?", "How hard should I train?", "When should I go to bed?"]

    var body: some View {
        let r = store.readiness
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BrandBadge(size: 28, gradientRing: true)
                Caps("Daily Outlook", size: 12)
            }
            Text(r.title)
                .font(Broop.Typeface.demi(17))
                .foregroundStyle(Broop.Palette.textPrimary)
            Text(r.message)
                .font(Broop.Typeface.regular(14))
                .foregroundStyle(Broop.Palette.textBody)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Caps("Ask Coach", size: 10, color: Broop.Palette.textSecondary).padding(.top, 8)
            ForEach(prompts, id: \.self) { prompt in
                Text(prompt)
                    .font(Broop.Typeface.medium(14))
                    .foregroundStyle(Broop.Palette.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Broop.Radius.row, style: .continuous).fill(Broop.Palette.row))
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Broop.Palette.card.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
