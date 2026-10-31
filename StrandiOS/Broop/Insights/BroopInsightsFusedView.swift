#if os(iOS)
import SwiftUI
import StrandAnalytics

// Your Data, Fused: the best-sourced value per metric with its provenance, drawn like a WHOOP statistics
// list. Built by the same `AppModel.buildTodayFusedRecord()` the host calls; a conflict opens the
// side-by-side compare sheet. Nothing is merged or averaged here, only shown.

struct BroopInsightsFusedView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @State private var record = FusedRecord(rows: [], dayOwner: nil, contributingSourceCount: 0)
    @State private var loaded = false
    @State private var comparing: FusedRow?

    private var temperature: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }
    private var multiSource: Bool { record.contributingSourceCount > 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    BroopCaps(String(localized: "Today"), size: 10.5, color: BroopPalette.textSecondary)
                    BroopInsightsHeadline(text: String(localized: "Your best-sourced record"), size: 26)
                    BroopInsightsBody(text: multiSource
                        ? String(localized: "The best signal per metric, from \(record.contributingSourceCount) sources. Everything stays on this device.")
                        : String(localized: "Your record, on this device."),
                        color: BroopPalette.textSecondary)
                }
                .padding(.top, 8)
                if multiSource {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.system(size: 13))
                        Text(verbatim: record.dayOwner.map { String(localized: "Today's scores owned by \($0.displayName)") }
                             ?? String(localized: "Scores still calibrating, no single day-owner yet"))
                            .font(BroopType.medium(13))
                    }
                    .foregroundStyle(BroopPalette.textBody)
                    .padding(.top, 16)
                }
                content.padding(.top, 22)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.system(size: 11))
                        Text("Fused on this device. Nothing leaves it: no account, no cloud.").font(BroopType.regular(12.5))
                    }
                    .foregroundStyle(BroopPalette.textSecondary)
                    BroopInsightsBody(text: String(localized: "Broop picks the best-sourced number and shows you where each came from. It's for wellness and curiosity. It doesn't diagnose or replace medical advice."),
                                      size: 12, color: BroopPalette.textTertiary)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .broopInsightsChrome(String(localized: "Your data, fused"))
        .task(id: repo.refreshSeq) {
            // The app model is read, not observed: it republishes about once a second.
            if let model = AppModel.shared { record = await model.buildTodayFusedRecord() }
            loaded = true
        }
        .sheet(item: $comparing) { row in
            BroopInsightsFusedCompare(row: row, temperature: temperature)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var content: some View {
        if !loaded {
            ProgressView().tint(BroopPalette.textSecondary).frame(maxWidth: .infinity).padding(.top, 30)
        } else if record.rows.isEmpty {
            BroopInsightsNote(symbol: "square.stack.3d.up", title: String(localized: "Nothing to fuse yet"),
                              text: String(localized: "Import a WHOOP export, Apple Health or a second band and your best-sourced record builds here, on this device."))
        } else {
            VStack(spacing: 0) {
                BroopListHeader(title: String(localized: "Metric"), trailing: multiSource ? String(localized: "Source") : nil)
                    .padding(.bottom, 6)
                ForEach(Array(record.rows.enumerated()), id: \.element.id) { i, row in
                    rowView(row)
                    if i < record.rows.count - 1 { BroopHairline() }
                }
            }
        }
    }

    private func rowView(_ row: FusedRow) -> some View {
        let p = row.point
        return Button { if p.agreement == .conflict { comparing = row } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(row.label)).font(BroopType.medium(15)).foregroundStyle(BroopPalette.textPrimary)
                    Spacer()
                    Text(verbatim: FusionFormat.value(p.value, metricKey: p.metric, temperature: temperature))
                        .font(BroopType.number(19)).foregroundStyle(BroopPalette.textPrimary)
                }
                if multiSource {
                    HStack(spacing: 6) {
                        Text(verbatim: String(localized: "from \(p.winningSource.displayName)"))
                            .font(BroopType.demi(12)).foregroundStyle(BroopPalette.textBody)
                        if let reason = p.contributors.first?.reason {
                            Text(verbatim: "· \(reason)").font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                        }
                        Spacer()
                    }
                    agreement(p)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(p.agreement == .conflict ? Text("Compare sources") : Text(""))
    }

    @ViewBuilder private func agreement(_ p: FusedMetricPoint) -> some View {
        let other = p.contributors.dropFirst().first
        switch p.agreement {
        case .single:
            EmptyView()
        case .agree:
            if let other {
                Text("\(other.source.displayName) agrees: \(FusionFormat.value(other.value, metricKey: p.metric, temperature: temperature))")
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
            }
        case .minorDelta:
            if let other {
                HStack(spacing: 8) {
                    BroopInsightsChip(text: String(localized: "Differs slightly"), color: BroopPalette.textBody)
                    Text(verbatim: "\(other.source.displayName): \(FusionFormat.value(other.value, metricKey: p.metric, temperature: temperature))")
                        .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        case .conflict:
            HStack(spacing: 8) {
                BroopInsightsChip(text: String(localized: "Sources differ"), color: BroopInsightsPalette.hurts)
                Text(verbatim: other.map { String(localized: "\($0.source.displayName) says \(FusionFormat.value($0.value, metricKey: p.metric, temperature: temperature)). Tap to compare") }
                     ?? String(localized: "Tap to compare"))
                    .font(BroopType.regular(12)).foregroundStyle(BroopPalette.textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(BroopPalette.textTertiary)
            }
        }
    }
}

/// Every source's value side by side, the one in use marked with its reason.
struct BroopInsightsFusedCompare: View {
    let row: FusedRow
    let temperature: TemperatureUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = row.point
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BroopInsightsBody(text: String(localized: "Your bands report different numbers. Here's every source, and the one Broop is using."),
                                      color: BroopPalette.textSecondary)
                    VStack(spacing: 0) {
                        ForEach(Array(p.contributors.enumerated()), id: \.offset) { i, c in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        BroopCaps(c.source.displayName, size: 11)
                                        if i == 0 { BroopInsightsChip(text: String(localized: "Using"), color: BroopInsightsPalette.helps) }
                                    }
                                    Text(verbatim: c.reason).font(BroopType.regular(12)).foregroundStyle(BroopPalette.textTertiary)
                                }
                                Spacer()
                                Text(verbatim: FusionFormat.value(c.value, metricKey: p.metric, temperature: temperature))
                                    .font(BroopType.number(19))
                                    .foregroundStyle(i == 0 ? BroopPalette.textPrimary : BroopPalette.textSecondary)
                            }
                            .padding(.vertical, 12)
                            if i < p.contributors.count - 1 { BroopHairline() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BroopPalette.card))
                    if let w = p.contributors.first {
                        BroopInsightsBody(text: String(localized: "Broop shows the \(w.source.displayName) reading because it \(w.reason) for this metric: a higher-trust source here, not a verdict that the others are wrong."),
                                          size: 13, color: BroopPalette.textSecondary)
                    }
                }
                .padding(BroopMetrics.page)
            }
            .background(BroopBackground())
            .broopInsightsChrome(row.label)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("Done").font(BroopType.demi(16)) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
