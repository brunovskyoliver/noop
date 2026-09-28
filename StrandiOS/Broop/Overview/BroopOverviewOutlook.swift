#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

/// Daily Outlook, in the shape of WHOOP Coach's morning outlook: a warm gradient head, a greeting, the
/// readiness read for the selected day, key insights as bullets with the figures in bold, and an
/// "Ask Coach" field that hands off to Coach. Everything shown is the snapshot the dials use.
struct BroopOutlookSheet: View {
    @EnvironmentObject private var store: BroopStore
    let onAskCoach: (() -> Void)?

    var body: some View {
        let snap = store.snapshot
        let evening = store.dayOffset > 0 || Calendar.current.component(.hour, from: Date()) >= 17
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BroopBadge(size: 30, gradientRing: true)
                BroopCaps(evening ? String(localized: "Day in Review") : String(localized: "Daily Outlook"), size: 11.5)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                Spacer()
                Text(verbatim: store.selectedLogicalDay.formatted(
                    .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.activeLocale)).uppercased())
                    .font(BroopType.caps(10.5))
                    .tracking(1.1)
                    .foregroundStyle(BroopPalette.textBody)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: greeting(evening: evening))
                        .font(BroopType.demi(22))
                        .foregroundStyle(BroopPalette.textPrimary)
                    if let readiness = snap?.readiness, readiness.level != .insufficient {
                        Text(verbatim: readiness.headline + ". " + readiness.summary)
                            .font(BroopType.medium(16))
                            .foregroundStyle(BroopPalette.textBody)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(snap?.chargeDisplay.calibrationDetail
                             ?? String(localized: "Not enough history yet for an outlook. Keep wearing the strap overnight."))
                            .font(BroopType.medium(16))
                            .foregroundStyle(BroopPalette.textBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    let facts = numbers(snap)
                    if !facts.isEmpty {
                        heading(String(localized: "Your Numbers"))
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in bullet(fact) }
                    }
                    if let signals = snap?.readiness?.signals, !signals.isEmpty, snap?.readiness?.level != .insufficient {
                        heading(String(localized: "Key Insights"))
                        ForEach(Array(signals.enumerated()), id: \.offset) { _, s in
                            bullet(Text(verbatim: s.label + ": ").font(BroopType.demi(15)).foregroundColor(BroopPalette.textPrimary)
                                   + Text(verbatim: s.detail).foregroundColor(BroopPalette.textBody),
                                   dot: BroopVitals.flagColor(s.flag))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            if let onAskCoach {
                HStack(spacing: 12) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(BroopPalette.textPrimary)
                    Button(action: onAskCoach) {
                        HStack {
                            Text("Ask Coach anything")
                                .font(BroopType.medium(15))
                                .foregroundStyle(BroopPalette.textSecondary)
                            Spacer()
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(BroopPalette.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [BroopOverviewPalette.coachStart, Color(broopHex: 0x5AD8FF)],
                                                             startPoint: .leading, endPoint: .trailing), lineWidth: 1.6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BroopPressableStyle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(stops: [
                .init(color: evening ? Color(broopHex: 0x4A416F) : Color(broopHex: 0x7D7263), location: 0),
                .init(color: evening ? Color(broopHex: 0x2A3050) : Color(broopHex: 0x3E4A55), location: 0.3),
                .init(color: BroopPalette.bgMid, location: 0.62),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func greeting(evening: Bool) -> String {
        if store.dayOffset > 0 { return String(localized: "Here's how the day went.") }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return String(localized: "Good morning.") }
        return evening ? String(localized: "Good evening.") : String(localized: "Good afternoon.")
    }

    private func heading(_ text: String) -> some View {
        Text(verbatim: text)
            .font(BroopType.demi(17))
            .foregroundStyle(BroopPalette.textPrimary)
            .padding(.top, 8)
    }

    private func bullet(_ text: Text, dot: Color = BroopPalette.textSecondary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(dot).frame(width: 5, height: 5).padding(.top, 8)
            text
                .font(BroopType.medium(15))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The day's figures as sentences with the number in bold, from the same snapshot as the dials.
    private func numbers(_ snap: BroopSnapshot?) -> [Text] {
        guard let snap else { return [] }
        var out: [Text] = []
        func line(_ bold: String, _ rest: String) -> Text {
            Text(verbatim: bold).font(BroopType.demi(15)).foregroundColor(BroopPalette.textPrimary)
                + Text(verbatim: rest).foregroundColor(BroopPalette.textBody)
        }
        if let charge = snap.charge {
            out.append(line("\(BroopFormat.whole(charge))% " + String(localized: "Charge"),
                            " " + String(localized: "for the day.")))
        }
        if let rest = snap.rest {
            var tail = " " + String(localized: "from last night")
            if let asleep = snap.asleepMinutes, let need = snap.needMinutes {
                tail += String(localized: ": \(BroopFormat.duration(asleep)) asleep of \(BroopFormat.duration(need)) needed")
            }
            out.append(line("\(BroopFormat.whole(rest))% " + String(localized: "Rest"), tail + "."))
        }
        if let effort = snap.effort {
            var tail = " " + String(localized: "so far")
            if let target = BroopOverviewEffortTarget(charge: snap.charge), snap.effortMax == 21 {
                tail += String(localized: ", with a target of \(target.range.lowerBound) to \(target.range.upperBound) for your Charge")
            }
            out.append(line(BroopScore.effort.format(effort) + " " + String(localized: "Effort"), tail + "."))
        }
        return out
    }
}
#endif
