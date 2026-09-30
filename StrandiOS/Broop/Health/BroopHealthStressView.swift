#if os(iOS)
import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign

/// Reads the same day analysis as Home, Health and the persisted Mind summaries.
struct BroopHealthStressView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @State private var dayOffset = 0
    @State private var day: StressMonitor.DayResult?
    @State private var loaded = false
    @State private var showInfo = false
    @State private var showAdvanced = false

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: -dayOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: BroopMetrics.section) {
                BroopHealthDateNav(label: dayOffset == 0 ? String(localized: "Today") : date.formatted(date: .abbreviated, time: .omitted),
                                   canGoBack: dayOffset < 180, canGoForward: dayOffset > 0,
                                   onBack: { dayOffset += 1 }, onForward: { dayOffset -= 1 })
                BroopHealthStressGauge(day: day, isToday: dayOffset == 0)
                if let day {
                    BroopHealthStressTimeline(epochs: day.epochs)
                    totals(day.summary)
                    VStack(alignment: .leading, spacing: BroopMetrics.page) {
                        HStack {
                            BroopCaps(String(localized: "Sleep stress"), size: 13)
                            Spacer()
                            Text(verbatim: day.summary.sleepStressPct.map { String(format: "%.0f%%", $0) } ?? "--")
                                .font(BroopType.number(24))
                        }
                        Text(day.summary.sleepStressPct == nil
                             ? "Sleep stress needs heart-rate coverage for at least half of your main sleep. Missing measurements do not lower Rest."
                             : "Share of measured main sleep in the high stress band. Lower is better. This contributes to Rest when Rest v2 is enabled in Scoring.")
                            .font(BroopType.regular(14)).foregroundStyle(BroopPalette.textSecondary)
                    }.padding(BroopMetrics.page).background(BroopPalette.card, in: RoundedRectangle(cornerRadius: BroopMetrics.cardRadius))
                } else {
                    Text(loaded ? "No heart-rate history for this day." : "Reading stress history…")
                        .font(BroopType.medium(15)).foregroundStyle(BroopPalette.textSecondary)
                }
                if coachEnabled {
                    Button {
                        router.openCoach(asking: CoachAskAbout.question(.stress, daysAgo: dayOffset, day: date),
                                     aboutDay: CoachAskAbout.dayKey(daysAgo: dayOffset, day: date), coach: coach)
                    } label: {
                        BroopHealthRow(symbol: "sparkles", title: String(localized: "Ask Coach"))
                    }.buttonStyle(BroopPressableStyle())
                }
                NavigationLink(value: BroopScreen.breathe) {
                    BroopHealthRow(symbol: "wind", title: String(localized: "Guided breathing"), detail: String(localized: "Increase relaxation or alertness"))
                }.buttonStyle(BroopPressableStyle())
                Button { showAdvanced = true } label: {
                    BroopHealthRow(symbol: "waveform.path.ecg", title: String(localized: "Advanced HRV and history"), detail: String(localized: "Classic stress analysis"))
                }.buttonStyle(BroopPressableStyle())
            }
            .padding(.horizontal, BroopMetrics.page)
            .padding(.bottom, BroopMetrics.tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            BroopHealthHeader(title: String(localized: "Stress Monitor")) {
                BroopHealthHeaderIcon(symbol: "info.circle", label: String(localized: "Stress method")) { showInfo = true }
            }
        }
        .broopHealthScreen()
        .task(id: "\(dayOffset)|\(repo.refreshSeq)") {
            day = nil
            loaded = false
            let value = await repo.stressDayAnalysis(dayKey: Repository.localDayKey(date))
            guard !Task.isCancelled else { return }
            day = value
            loaded = true
        }
        .sheet(isPresented: $showInfo) {
            ScrollView {
                Text(verbatim: BroopMethodText.stress)
                    .font(BroopType.regular(16)).foregroundStyle(BroopPalette.textBody).padding(BroopMetrics.page)
            }.broopSheetBar(String(localized: "Stress method")) { showInfo = false }
        }
        .sheet(isPresented: $showAdvanced) {
            NavigationStack { StressView().broopSheetBar(String(localized: "Advanced stress")) { showAdvanced = false } }
        }
    }

    private func totals(_ summary: StressDaySummary) -> some View {
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            BroopCaps(String(localized: "Waking time"), size: 13)
            HStack {
                band(String(localized: "Low"), minutes: summary.lowMin, color: BroopHealthPalette.stressLow, measured: summary.hasWaking)
                Spacer()
                band(String(localized: "Medium"), minutes: summary.medMin, color: BroopHealthPalette.stressMedium, measured: summary.hasWaking)
                Spacer()
                band(String(localized: "High"), minutes: summary.highMin, color: BroopHealthPalette.stressHigh, measured: summary.hasWaking)
            }
            Text(summary.hasWaking ? "\(summary.scoredMin) minutes measured. Sleep, activity and gaps are excluded."
                 : "At least 30 minutes of waking measurements are needed.")
                .font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
        }.padding(BroopMetrics.page).background(BroopPalette.card, in: RoundedRectangle(cornerRadius: BroopMetrics.cardRadius))
    }

    private func band(_ title: String, minutes: Int, color: Color, measured: Bool) -> some View {
        VStack(alignment: .leading, spacing: BroopMetrics.innerRadius) {
            BroopCaps(title, size: 11, color: color)
            Text(verbatim: measured ? "\(minutes / 60)h \(minutes % 60)m" : "--").font(BroopType.number(23))
        }
    }
}

/// Only this child observes live stress changes.
private struct BroopHealthStressGauge: View {
    let day: StressMonitor.DayResult?
    let isToday: Bool
    @ObservedObject private var live = BroopHealthStressLive.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared

    var body: some View {
        let reading = BroopHealthStressNow.resolve(live: isToday ? live.reading : nil, latest: day?.latest)
        ZStack {
            BroopHealthStressArc(value: reading?.level)
                .animation(reading?.source == .live && reading?.level != nil
                           ? StrandMotion.drawIn(reduced: motion.poseStill(reduceMotion)) : nil,
                           value: reading?.level)
            VStack(spacing: BroopMetrics.innerRadius) {
                Text(verbatim: reading?.level.map(StressTrace.formatLevel) ?? "--")
                    .font(BroopType.number(60)).foregroundStyle(BroopPalette.textPrimary)
                BroopCaps(reading?.active == true ? String(localized: "Activity / elevated pulse") : reading?.level.map { StressBand(score: $0).title } ?? String(localized: "No reading"), size: 13)
                Text(reading?.source == .live ? "Live" : "Latest measured")
                    .font(BroopType.medium(13)).foregroundStyle(BroopPalette.textSecondary)
                if let time = reading?.time, reading?.source != .live {
                    Text(time, style: .time).font(BroopType.regular(13)).foregroundStyle(BroopPalette.textSecondary)
                }
            }
        }
        .frame(height: 240)
        .broopHealthStressLive(reference: isToday ? day?.wake : nil, day: isToday ? day?.day : nil)
    }
}

private struct BroopHealthStressTimeline: View {
    let epochs: [StressMonitor.Epoch]

    var body: some View {
        VStack(alignment: .leading, spacing: BroopMetrics.page) {
            BroopCaps(String(localized: "Day timeline"), size: 13)
            Chart {
                ForEach(epochs, id: \.startTs) { epoch in
                    if epoch.state == .sleep || epoch.state == .activity {
                        RectangleMark(xStart: .value("Start", Date(timeIntervalSince1970: Double(epoch.startTs))),
                                      xEnd: .value("End", Date(timeIntervalSince1970: Double(epoch.startTs + StressMonitor.epochSeconds))),
                                      yStart: .value("Low", 0), yEnd: .value("High", 3))
                            .foregroundStyle((epoch.state == .sleep ? BroopPalette.rest : BroopPalette.effort).opacity(0.18))
                    }
                    if let value = epoch.level {
                        PointMark(x: .value("Time", Date(timeIntervalSince1970: Double(epoch.startTs))), y: .value("Stress", value))
                            .symbolSize(7).foregroundStyle(BroopHealthPalette.stress(value))
                    }
                }
            }
            .chartYScale(domain: 0...3)
            .chartYAxis { AxisMarks(values: [0, 1, 2, 3]) }
            .frame(height: 160)
            HStack {
                Label("Sleep", systemImage: "bed.double.fill").foregroundStyle(BroopPalette.rest)
                Spacer()
                Label("Activity", systemImage: "figure.run").foregroundStyle(BroopPalette.effort)
            }.font(BroopType.regular(12))
        }
    }
}

private struct BroopHealthStressArc: View, Animatable {
    var value: Double?

    // Canvas needs an interpolated value to move the needle between packet updates.
    var animatableData: Double {
        get { value ?? 0 }
        set { if value != nil { value = newValue } }
    }

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 10
            let start = Angle.degrees(150), sweep = 240.0
            let gradient = Gradient(stops: [
                .init(color: BroopHealthPalette.stressLow, location: 0),
                .init(color: BroopHealthPalette.stressMedium, location: 0.5),
                .init(color: BroopHealthPalette.stressHigh, location: 1),
            ])
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: start, endAngle: .degrees(150 + sweep), clockwise: false)
            // Conic shading mapped onto the sweep.
            let shading = GraphicsContext.Shading.conicGradient(
                Gradient(stops: gradient.stops.map { .init(color: $0.color, location: $0.location * sweep / 360) }),
                center: c, angle: start)
            // A wide dim band, then a thin bright outer edge.
            ctx.drawLayer { layer in
                layer.opacity = 0.22
                layer.stroke(arc, with: shading, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
            }
            var edge = Path()
            edge.addArc(center: c, radius: r + 6.5, startAngle: start, endAngle: .degrees(150 + sweep), clockwise: false)
            ctx.stroke(edge, with: .conicGradient(
                Gradient(stops: gradient.stops.map { .init(color: $0.color, location: $0.location * sweep / 360) }),
                center: c, angle: start), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            if let value {
                let t = min(max(value / 3, 0), 1)
                let a = (150 + sweep * t) * .pi / 180
                let outer = CGPoint(x: c.x + CGFloat(cos(a)) * (r + 7), y: c.y + CGFloat(sin(a)) * (r + 7))
                let inner = CGPoint(x: c.x + CGFloat(cos(a)) * (r - 28), y: c.y + CGFloat(sin(a)) * (r - 28))
                var needle = Path()
                needle.move(to: outer)
                needle.addLine(to: inner)
                ctx.stroke(needle, with: .linearGradient(Gradient(colors: [BroopPalette.textPrimary, BroopPalette.textPrimary.opacity(0)]),
                                                         startPoint: outer, endPoint: inner),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}


#endif
