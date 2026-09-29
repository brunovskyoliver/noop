#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign

/// The Health-tab Mind card: Resilience level and Cumulative Stress level side by side, from the same
/// `BroopMindData` resolver the Mind screen uses. Loads itself so the Health tab's own load stays as is.
struct BroopMindCard: View {
    @EnvironmentObject private var repo: Repository
    @State private var data = BroopMindData()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BroopHealthCardTitle(title: String(localized: "Mind"),
                                 trailing: data.checkInDue && data.loaded ? String(localized: "Check-in due") : nil)
            HStack(spacing: 0) {
                column(title: String(localized: "Resilience"),
                       value: data.resilience.map { BroopMindCopy.name($0.level) },
                       color: data.resilience.map { BroopMindCopy.color($0.level) },
                       pending: "\(data.resilienceStressDays)/\(ResilienceEngine.minStressDays) " + String(localized: "days"))
                Rectangle().fill(BroopPalette.hairline).frame(width: 1, height: 44)
                column(title: String(localized: "Cumulative Stress"),
                       value: data.cumulative.map { BroopMindCopy.name($0.level) },
                       color: data.cumulative.map { BroopMindCopy.color($0.level) },
                       pending: "\(data.cumulativeStressDays)/\(CumulativeStressEngine.minDays) " + String(localized: "days"))
                    .padding(.leading, 16)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: BroopMetrics.cardRadius, style: .continuous).fill(BroopPalette.card))
        .task(id: "\(repo.refreshSeq)|\(repo.mindCheckInRevision)") { data = await BroopMindData.load(repo: repo) }
    }

    private func column(title: String, value: String?, color: Color?, pending: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            BroopCaps(title, size: 10, color: BroopPalette.textSecondary)
            if let value {
                Text(verbatim: value).font(BroopType.demi(20)).foregroundStyle(color ?? BroopPalette.textPrimary)
            } else {
                Text(verbatim: data.loaded ? String(localized: "Calibrating") + " · " + pending : "--")
                    .font(BroopType.medium(14)).foregroundStyle(BroopPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
