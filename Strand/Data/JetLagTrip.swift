import Foundation
import StrandAnalytics

/// A saved pre-travel plan. Sleep timing is captured from the shared tonight plan when the trip is saved.
struct JetLagTrip: Codable, Equatable, Sendable {
    let travelDate: Date
    let originTimeZone: String
    let destinationOffsetMinutes: Int
    let bedMinute: Int
    let wakeMinute: Int

    struct Day: Identifiable, Sendable {
        let date: Date
        let timing: CircadianEngine.DayPlan
        var id: Int { timing.dayIndex }
    }

    struct Plan: Sendable {
        let direction: CircadianEngine.ShiftDirection
        let days: [Day]
    }

    /// All displayed dates and windows use the origin's clock. Destination offset is for the travel date.
    nonisolated func resolve() -> Plan? {
        guard let zone = TimeZone(identifier: originTimeZone),
              (-720...840).contains(destinationOffsetMinutes),
              (0..<1440).contains(bedMinute), (0..<1440).contains(wakeMinute) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let departure = calendar.startOfDay(for: travelDate)
        let shift = Double(destinationOffsetMinutes * 60 - zone.secondsFromGMT(for: departure)) / 3600
        // The simple stepped engine does not choose a direction for date-line travel.
        guard abs(shift) <= 12 else { return nil }
        let result = CircadianEngine.planShift(shiftHours: shift,
                                               currentSleepHour: Double(bedMinute) / 60,
                                               currentWakeHour: Double(wakeMinute) / 60)
        let days = result.days.compactMap { day -> Day? in
            guard let date = calendar.date(byAdding: .day, value: day.dayIndex - result.estimatedDays - 1,
                                            to: departure) else { return nil }
            return Day(date: date, timing: day)
        }
        return Plan(direction: result.direction, days: days)
    }
}

extension Repository {
    func jetLagPlan(trip: JetLagTrip) async -> JetLagTrip.Plan? {
        await CancellableAnalysis.run { trip.resolve() } ?? nil
    }
}
