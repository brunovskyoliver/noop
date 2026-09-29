#if os(iOS)
import SwiftUI
import StrandAnalytics

/// The Body Clock card on the Broop sleep screen: last night's window against the window the body clock
/// wanted, on one thin 24-hour dial (midnight at the top), in the flat Broop dial style.
///
/// Reads `AppModel.circadianPhase` in this leaf only, so the model's once-a-second republish re-renders the
/// dial and not the sleep screen (the classic `BodyClockDialSection` rule). The window, the offset and the
/// chronotype come from `CircadianEngine`; the caption and chronotype words from `BodyClockDialCard`'s static
/// helpers, so the classic and Broop dials state the same comparison. Hidden for an unreadable fit, and
/// when the engine has no ideal window for the night (a non-positive or full-day length).
struct BroopFinalABodyClockSection: View {
    @EnvironmentObject private var appModel: AppModel
    let actualBedHour: Double
    let actualWakeHour: Double

    var body: some View {
        if let phase = appModel.circadianPhase, phase.confidence != .unreadable {
            BroopFinalABodyClockCard(estimate: phase, actualBedHour: actualBedHour, actualWakeHour: actualWakeHour)
        }
    }
}

struct BroopFinalABodyClockCard: View {
    let estimate: CircadianEngine.PhaseEstimate
    let actualBedHour: Double
    let actualWakeHour: Double

    private var durationHours: Double {
        let d = (actualWakeHour - actualBedHour).truncatingRemainder(dividingBy: 24)
        return d <= 0 ? d + 24 : d
    }

    private var ideal: (bedHour: Double, wakeHour: Double)? {
        CircadianEngine.idealSleepWindow(tempMinHour: estimate.tempMinHour, durationHours: durationHours)
    }

    private var offsetHours: Double {
        CircadianEngine.sleepWindowOffsetHours(tempMinHour: estimate.tempMinHour, actualWakeHour: actualWakeHour)
    }

    var body: some View {
        if let ideal {
            VStack(alignment: .leading, spacing: 14) {
                BroopOverviewSectionTitle(title: String(localized: "Body Clock"),
                                          subtitle: Text("Last night against your clock").foregroundColor(BroopPalette.textSecondary)) {
                    if let chronotype = CircadianEngine.chronotype(estimate) {
                        BroopFinalAChip(text: BodyClockDialCard.chronotypeLabel(chronotype), tint: BroopPalette.textBody)
                    }
                }
                BroopOverviewCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 18) {
                            BroopFinalAClockDial(bedHour: actualBedHour, wakeHour: actualWakeHour,
                                                 idealBed: ideal.bedHour, idealWake: ideal.wakeHour)
                                .frame(width: 150, height: 150)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("Body clock dial"))
                            VStack(alignment: .leading, spacing: 14) {
                                window(label: String(localized: "Last night"), from: actualBedHour, to: actualWakeHour, dashed: false)
                                window(label: String(localized: "Your clock"), from: ideal.bedHour, to: ideal.wakeHour, dashed: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        BroopHairline()
                        Text(verbatim: BodyClockDialCard.alignmentText(offsetHours: offsetHours))
                            .font(BroopType.demi(17))
                            .foregroundStyle(BroopPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func window(label: String, from: Double, to: Double, dashed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                BroopFinalALegendStroke(dashed: dashed).frame(width: 18, height: 4)
                BroopCaps(label, size: 9.5, color: BroopPalette.textSecondary)
            }
            Text(verbatim: "\(Self.clock(from)) – \(Self.clock(to))")
                .font(BroopType.number(17))
                .foregroundStyle(BroopPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// A fractional clock hour in the app's 12/24-hour convention.
    static func clock(_ hour: Double) -> String {
        var h = hour.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        var hh = Int(h)
        var mm = Int(((h - Double(hh)) * 60).rounded())
        if mm == 60 { mm = 0; hh = (hh + 1) % 24 }
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.year = 2001; c.month = 1; c.day = 1; c.hour = hh; c.minute = mm
        guard let date = c.date else { return String(format: "%d:%02d", hh, mm) }
        return AppClock.hourMinute(date)
    }
}

/// The swatch beside each window, drawn with the arc's own stroke so the key can't drift from the dial.
private struct BroopFinalALegendStroke: View {
    let dashed: Bool
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(p, with: .color(dashed ? BroopPalette.textSecondary : BroopPalette.rest),
                       style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: dashed ? [3, 3] : []))
        }
    }
}

/// Thin 24-hour dial: a flat track with last night's arc, the clock's window as a dashed outer arc, ticks
/// every six hours (midnight longer) with 00 / 06 / 12 / 18, and a small bed at sleep onset. Each band has
/// its own radius so the dashes never run into the ticks.
struct BroopFinalAClockDial: View {
    let bedHour: Double
    let wakeHour: Double
    let idealBed: Double
    let idealWake: Double

    var body: some View {
        Canvas { ctx, size in
            let side: CGFloat = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rim: CGFloat = side / 2 - 2
            let label: CGFloat = rim - 11
            let reference: CGFloat = rim - 24
            let night: CGFloat = rim - 34
            let glyphR: CGFloat = rim - 47

            // Track under the night arc.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - night, y: c.y - night, width: night * 2, height: night * 2)),
                       with: .color(BroopPalette.track), lineWidth: 6)
            // Ticks.
            for tick in stride(from: 0.0, to: 24.0, by: 6.0) {
                let a = Self.angle(tick).radians
                let len: CGFloat = tick == 0 ? 5 : 3
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * (rim - len), y: c.y + sin(a) * (rim - len)))
                p.addLine(to: CGPoint(x: c.x + cos(a) * rim, y: c.y + sin(a) * rim))
                ctx.stroke(p, with: .color(tick == 0 ? BroopPalette.textPrimary : BroopPalette.textTertiary),
                           lineWidth: tick == 0 ? 1.5 : 1)
                var numeral = ctx.resolve(Text(String(format: "%02d", Int(tick))).font(BroopType.number(9)))
                numeral.shading = .color(BroopPalette.textSecondary)
                ctx.draw(numeral, at: CGPoint(x: c.x + cos(a) * label, y: c.y + sin(a) * label), anchor: .center)
            }
            // The clock's window, dashed; last night, solid.
            arc(ctx, c, reference, idealBed, idealWake, BroopPalette.textSecondary, 3, dashed: true)
            arc(ctx, c, night, bedHour, wakeHour, BroopPalette.rest, 6, dashed: false)
            // Bed at onset, inside the night arc.
            var bed = ctx.resolve(Image(systemName: "bed.double.fill"))
            bed.shading = .color(BroopPalette.textBody)
            let a = Self.angle(bedHour).radians
            let g: CGFloat = 11
            ctx.draw(bed, in: CGRect(x: c.x + cos(a) * glyphR - g / 2, y: c.y + sin(a) * glyphR - g / 2, width: g, height: g))
        }
    }

    private static func angle(_ hour: Double) -> Angle { .degrees(hour / 24 * 360 - 90) }

    private static func sweep(_ from: Double, _ to: Double) -> Double {
        let d = (to - from).truncatingRemainder(dividingBy: 24)
        return d <= 0 ? d + 24 : d
    }

    private func arc(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ from: Double, _ to: Double,
                     _ color: Color, _ width: CGFloat, dashed: Bool) {
        let start = Self.angle(from)
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: start,
                 endAngle: .degrees(start.degrees + Self.sweep(from, to) / 24 * 360), clockwise: false)
        ctx.stroke(p, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: dashed ? [5, 4] : []))
    }
}
#endif
