#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - Health

/// Broop Health Monitor: last night's vitals against the wearer's range, then links to every
/// body-related classic screen. The readings come from `BroopVitals.readings(repo:)`, the same resolver
/// the classic Health screen uses, so the two screens cannot disagree about what is in range.
struct BroopHealthView: View {
    @EnvironmentObject private var repo: Repository

    var body: some View {
        let readings = BroopVitals.readings(repo: repo)
        ScrollView {
            VStack(spacing: 0) {
                BroopPageHeader(text: String(localized: "Health Monitor"))
                summary(readings).padding(.top, 20)
                VStack(spacing: 12) {
                    BroopListHeader(title: String(localized: "Last night · vs. your range"))
                    VStack(spacing: 8) {
                        ForEach(readings) { reading in
                            NavigationLink(value: BroopScreen.health) {
                                BroopBodyVitalTile(reading: reading)
                            }
                            .buttonStyle(BroopPressableStyle())
                        }
                    }
                }
                .padding(.top, BroopMetrics.section)
                VStack(spacing: 12) {
                    BroopListHeader(title: String(localized: "Monitors"))
                    VStack(spacing: 8) {
                        link(BroopScreen.health, "heart.text.square", String(localized: "Health details"))
                        link(BroopScreen.stress, "bolt.heart", String(localized: "Stress"))
                        link(BroopScreen.metricExplorer, "waveform.path.ecg", String(localized: "HRV & vitals explorer"))
                        link(BroopScreen.labBook, "books.vertical", String(localized: "Lab Book"))
                        link(BroopScreen.rhythm, "waveform.path", String(localized: "Rhythm"))
                        link(BroopScreen.fusedRecord, "square.stack.3d.up", String(localized: "Your Data, Fused"))
                    }
                }
                .padding(.top, BroopMetrics.section)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable { await repo.refresh() }
        .broopStatusBarScrim()
        .background(BroopBackground())
    }

    private func link<Value: Hashable>(_ value: Value, _ symbol: String, _ title: String) -> some View {
        NavigationLink(value: value) {
            BroopNavTile(symbol: symbol, title: title)
        }
        .buttonStyle(BroopPressableStyle())
    }

    @ViewBuilder
    private func summary(_ readings: [BodyVitalReading]) -> some View {
        let withData = readings.filter { $0.banding.band != .noData }
        let inRange = withData.filter { $0.banding.band == .inRange }
        let outliers = withData.filter { $0.banding.band == .outOfRange }
        VStack(spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(verbatim: withData.isEmpty ? "–" : "\(inRange.count)")
                    .font(BroopType.number(64))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .broopNumeral(64)
                Text(verbatim: "/\(withData.count)")
                    .font(BroopType.number(28))
                    .foregroundStyle(BroopPalette.textSecondary)
            }
            BroopCaps(statusLine(withData: withData.count, outliers: outliers.count), size: 11,
                      color: withData.isEmpty ? BroopPalette.textSecondary
                          : (outliers.isEmpty ? BroopPalette.teal : BroopPalette.warning))
            Text(verbatim: bodyLine(withData: withData.count, outliers: outliers))
                .font(BroopType.regular(14))
                .foregroundStyle(BroopPalette.textBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusLine(withData: Int, outliers: Int) -> String {
        if withData == 0 { return String(localized: "No vitals yet") }
        if outliers == 0 { return String(localized: "Within range") }
        if outliers == withData { return String(localized: "Outside range") }
        return String(localized: "Metrics within range")
    }

    private func bodyLine(withData: Int, outliers: [BodyVitalReading]) -> String {
        if withData == 0 {
            return String(localized: "Wear your strap overnight to see your vitals against your range.")
        }
        if outliers.isEmpty { return String(localized: "Nothing unusual last night.") }
        let names = ListFormatter.localizedString(byJoining: outliers.map(\.label))
        return String(localized: "\(names) outside your usual range. One reading alone is rarely a concern; watch for two or more over several days.")
    }
}

/// One vital on a row tile: label, value, in-range badge, sparkline and the classic state caption.
private struct BroopBodyVitalTile: View {
    let reading: BodyVitalReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BroopCaps(reading.label, size: 10.5)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: reading.value.map(reading.format) ?? "–").font(BroopType.number(19))
                    if reading.value != nil && !reading.unit.isEmpty {
                        Text(verbatim: reading.unit)
                            .font(BroopType.number(11))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                .foregroundStyle(reading.value == nil ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                badge
            }
            if let points = reading.sparkline, points.count > 1 {
                BroopSparkline(values: points)
                    .stroke(BroopPalette.textPrimary.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 22)
            }
            Text(verbatim: reading.stateCaption)
                .font(BroopType.regular(12))
                .foregroundStyle(BroopPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.rowRadius, style: .continuous).fill(BroopPalette.row))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        switch reading.banding.band {
        case .inRange:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.pillInner))
        case .outOfRange:
            Image(systemName: "exclamationmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.bgBottom)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.warning))
        case .noData:
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(BroopPalette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(BroopPalette.track))
        }
    }
}

/// A plain polyline scaled to its own min/max.
private struct BroopSparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return path }
        let span = hi - lo
        let step = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let t = span > 0 ? (v - lo) / span : 0.5
            let point = CGPoint(x: rect.minX + CGFloat(i) * step, y: rect.maxY - CGFloat(t) * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

#endif
