#if os(iOS)
import SwiftUI
import StrandAnalytics

struct BroopHealthJetLagView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @AppStorage("broop.jetLag.activeTrip.v1") private var savedTrip = ""
    @State private var travelDate = Date()
    @State private var destinationOffset = 0
    @State private var plan: JetLagTrip.Plan?
    @State private var showInfo = false
    @State private var loaded = false

    private var activeTrip: JetLagTrip? {
        savedTrip.data(using: .utf8).flatMap { try? JSONDecoder().decode(JetLagTrip.self, from: $0) }
    }

    private var matchesSavedTrip: Bool {
        guard let trip = activeTrip else { return false }
        return Calendar.current.isDate(travelDate, inSameDayAs: trip.travelDate)
            && destinationOffset == trip.destinationOffsetMinutes
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BroopMetrics.page) {
                BroopCard {
                    VStack(alignment: .leading, spacing: BroopMetrics.page) {
                        DatePicker(String(localized: "Travel date"), selection: $travelDate, displayedComponents: .date)
                        BroopCaps(String(localized: "Destination UTC offset"), size: BroopMetrics.tileRadius,
                                  color: BroopPalette.textSecondary)
                        Picker(String(localized: "Destination UTC offset"), selection: $destinationOffset) {
                            ForEach(Array(stride(from: -720, through: 840, by: 15)), id: \.self) { minute in
                                Text(verbatim: Self.offsetLabel(minute)).tag(minute)
                            }
                        }
                        Text(String(localized: "Use the destination's UTC offset on your travel date, including daylight saving time."))
                            .font(BroopType.regular(BroopMetrics.tileRadius))
                            .foregroundStyle(BroopPalette.textSecondary)
                        Button(String(localized: "Save trip")) { save() }
                            .disabled(model.tonightPlan == nil)
                            .frame(minHeight: BroopMetrics.navHeight)
                        if matchesSavedTrip, let trip = activeTrip {
                            row(label: String(localized: "Sleep plan starting window"),
                                value: clock(Double(trip.bedMinute) / 60) + " – " + clock(Double(trip.wakeMinute) / 60))
                        } else if let sleep = model.tonightPlan {
                            row(label: String(localized: "Sleep plan starting window"),
                                         value: clock(Double(sleep.target.bedMinute) / 60) + " – " + clock(Double(sleep.wakeMinute) / 60))
                        }
                    }
                }
                if let trip = activeTrip, matchesSavedTrip {
                    Text(String(localized: "Before travel. All times use the origin clock: \(trip.originTimeZone)."))
                        .font(BroopType.regular(BroopMetrics.page))
                        .foregroundStyle(BroopPalette.textBody)
                    if !loaded {
                        ProgressView()
                    } else if let plan {
                        if plan.direction == .none {
                            BroopFootnote(text: String(localized: "No meaningful time shift for this trip."))
                        }
                        ForEach(plan.days) { day in
                            BroopCard {
                                VStack(alignment: .leading, spacing: BroopMetrics.gap) {
                                    Text(verbatim: dateLabel(day.date, zone: trip.originTimeZone))
                                        .font(BroopType.demi(BroopMetrics.page))
                                    row(label: String(localized: "Sleep / wake"),
                                                 value: clock(day.timing.targetSleepHour) + " / " + clock(day.timing.targetWakeHour))
                                    row(label: String(localized: "Seek bright light"),
                                                 value: clock(day.timing.brightLightStartHour) + " – " + clock(day.timing.brightLightEndHour))
                                    row(label: plan.direction == .advance ? String(localized: "Keep evening dim from")
                                                                                : String(localized: "Avoid bright morning light from"),
                                                 value: clock(day.timing.dimFromHour))
                                }
                            }
                        }
                    } else {
                        BroopFootnote(text: String(localized: "This simple planner supports time differences up to 12 hours. No plan is available for the saved trip."))
                    }
                    Button(String(localized: "Clear trip")) { savedTrip = ""; plan = nil }
                        .frame(minHeight: BroopMetrics.navHeight)
                }
                Button(String(localized: "How it works")) { showInfo = true }
                    .frame(minHeight: BroopMetrics.navHeight)
            }
            .padding(BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .broopScreenChrome(String(localized: "Jet-lag planner"))
        .task(id: savedTrip) {
            loaded = false
            plan = nil
            if let trip = activeTrip {
                travelDate = trip.travelDate
                destinationOffset = trip.destinationOffsetMinutes
                let result = await repo.jetLagPlan(trip: trip)
                guard !Task.isCancelled else { return }
                plan = result
            }
            loaded = true
        }
        .task { if model.tonightPlan == nil { await model.refreshTonightPlan() } }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                ScrollView {
                    BroopFootnote(text: String(localized: "Moves your saved sleep-plan window by up to one hour per day before travel. Seek morning light for earlier shifts, evening light for later shifts, and keep the opposite window dim. Dates and times use the origin clock. This guide cannot predict individual adaptation, flight sleep or date-line travel. It changes no alarm or reminder."))
                        .padding(BroopMetrics.page)
                }
                .broopScreenChrome(String(localized: "How it works"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { showInfo = false } } }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func save() {
        guard let sleep = model.tonightPlan else { return }
        let trip = JetLagTrip(travelDate: travelDate, originTimeZone: TimeZone.current.identifier,
                              destinationOffsetMinutes: destinationOffset,
                              bedMinute: sleep.target.bedMinute, wakeMinute: sleep.wakeMinute)
        if let data = try? JSONEncoder().encode(trip), let encoded = String(data: data, encoding: .utf8) {
            savedTrip = encoded
        }
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BroopMetrics.gap) {
            BroopCaps(label, size: BroopMetrics.tileRadius, color: BroopPalette.textSecondary)
            Text(verbatim: value).font(BroopType.number(BroopMetrics.page))
                .foregroundStyle(BroopPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func clock(_ hour: Double) -> String { BroopFinalABodyClockCard.clock(hour) }

    private func dateLabel(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private static func offsetLabel(_ minute: Int) -> String {
        String(format: "UTC%@%02d:%02d", minute < 0 ? "−" : "+", abs(minute) / 60, abs(minute) % 60)
    }
}
#endif
