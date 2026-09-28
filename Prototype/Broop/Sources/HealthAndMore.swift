import SwiftUI

/// Centred uppercase page title ("STRESS MONITOR" style).
struct PageHeader: View {
    let text: String
    var body: some View {
        Caps(text, size: 12)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.top, 8)
    }
}

struct NavTile: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    var body: some View {
        Tile(padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Broop.Palette.textPrimary)
                    .frame(width: 26)
                Caps(title, size: 11)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Broop.Typeface.demi(12))
                        .foregroundStyle(Broop.Palette.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Broop.Palette.textSecondary)
            }
        }
    }
}

struct NavTileList: View {
    let rows: [(String, String, String?)]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                NavigationLink { PlaceholderScreen(title: row.1) } label: {
                    NavTile(symbol: row.0, title: row.1, detail: row.2)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

struct HealthTabView: View {
    @EnvironmentObject var store: SampleStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    PageHeader(text: "Health Monitor")
                    DateNavigator().padding(.top, 8)
                    summary.padding(.top, 28)
                    VStack(spacing: 12) {
                        ListHeader(title: "Last night", trailing: "vs. 30-day range")
                        VStack(spacing: 8) {
                            ForEach(store.vitals) { VitalTile(vital: $0) }
                        }
                    }
                    .padding(.top, Broop.Space.section)
                    VStack(spacing: 12) {
                        ListHeader(title: "Monitors")
                        NavTileList(rows: [
                            ("waveform.path.ecg", "Stress", "Low"),
                            ("hourglass", "Vitality", "Body age 31"),
                            ("heart.text.square", "HRV status", "Balanced"),
                            ("circle.dotted.circle", "Cycle", nil),
                            ("testtube.2", "Lab book", nil),
                        ])
                    }
                    .padding(.top, Broop.Space.section)
                }
                .padding(.horizontal, Broop.Space.page)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .statusBarScrim()
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var summary: some View {
        let outliers = store.outliers
        let total = store.vitals.count
        let inRange = total - outliers.count
        return VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(inRange)").font(Broop.Typeface.number(64))
                Text("/\(total)").font(Broop.Typeface.number(28)).foregroundStyle(Broop.Palette.textSecondary)
            }
            .foregroundStyle(Broop.Palette.textPrimary)
            .numeral(64)
            Caps(outliers.isEmpty ? "Within range" : "Metrics within range", size: 11,
                 color: outliers.isEmpty ? Broop.Palette.teal : Broop.Palette.warning)
            Text(outliers.isEmpty
                 ? "Nothing unusual last night."
                 : "\(outliers.map(\.name).joined(separator: " and ")) outside your usual range. One reading alone is rarely a concern; watch for two or more over several days.")
                .font(Broop.Typeface.regular(14))
                .foregroundStyle(Broop.Palette.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
    }
}

struct VitalTile: View {
    let vital: Contributor

    var body: some View {
        Tile(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Caps(vital.name, size: 10.5)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(vital.text).font(Broop.Typeface.number(19))
                        if !vital.unit.isEmpty {
                            Text(vital.unit).font(Broop.Typeface.number(11)).foregroundStyle(Broop.Palette.textSecondary)
                        }
                    }
                    .foregroundStyle(Broop.Palette.textPrimary)
                    Image(systemName: vital.status == .typical ? "checkmark" : "exclamationmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(vital.status == .typical ? Broop.Palette.textPrimary : Broop.Palette.bgBottom)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(vital.status == .typical ? Broop.Palette.pillInner : vital.tint))
                }
                RangeBar(contributor: vital)
            }
        }
    }
}

struct MoreTabView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    PageHeader(text: "More")
                    NavTileList(rows: [
                        ("figure.strengthtraining.traditional", "Workouts & lifts", nil),
                        ("lightbulb", "Insights", nil),
                        ("alarm", "Alarms & sleep plan", nil),
                        ("wind", "Breathe & intervals", nil),
                    ])
                    .padding(.top, 16)
                    NavTileList(rows: [
                        ("dot.radiowaves.left.and.right", "Devices", "82%"),
                        ("externaldrive", "Data & backup", nil),
                        ("bolt.horizontal", "Automations", nil),
                        ("gearshape", "Settings", nil),
                    ])
                    .padding(.top, 24)
                    VStack(spacing: 10) {
                        Wordmark(size: 15)
                        Caps("Prototype · sample data", size: 9, color: Broop.Palette.textTertiary)
                    }
                    .padding(.top, 44)
                }
                .padding(.horizontal, Broop.Space.page)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .statusBarScrim()
            .background(BroopBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
