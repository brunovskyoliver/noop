#if os(iOS)
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Typical minutes for one stage over the trailing 30 scored days: the 25th–75th percentile band and the
/// mean. The same rule `SleepView.stageTypical` uses (nil under five nights), so both screens draw one
/// typical range.
struct BroopOverviewStageTypical: Equatable {
    let lo: Double
    let hi: Double
    let mean: Double

    static func compute(days: [DailyMetric], stage: SleepStage?) -> BroopOverviewStageTypical? {
        let values: [Double] = days.suffix(30).compactMap { d in
            switch stage {
            case nil: return d.totalSleepMin
            case .light?: return d.lightMin
            case .deep?: return d.deepMin
            case .rem?: return d.remMin
            case .awake?:
                guard let asleep = d.totalSleepMin, asleep > 0, var e = d.efficiency, e > 0 else { return nil }
                if e > 1.5 { e /= 100 }
                guard e > 0.3, e <= 1 else { return nil }
                return asleep * (1 - e) / e
            }
        }.filter { $0 > 0 }.sorted()
        guard values.count >= 5 else { return nil }
        func pct(_ p: Double) -> Double {
            let idx = p * Double(values.count - 1)
            let l = Int(idx.rounded(.down)), u = Int(idx.rounded(.up))
            let frac = idx - Double(l)
            return values[l] * (1 - frac) + values[u] * frac
        }
        return BroopOverviewStageTypical(lo: pct(0.25), hi: pct(0.75), mean: values.reduce(0, +) / Double(values.count))
    }
}

extension SleepStage {
    var broopColor: Color {
        switch self {
        case .awake: return BroopOverviewPalette.stageAwake
        case .light: return BroopOverviewPalette.stageLight
        case .deep: return BroopOverviewPalette.stageDeep
        case .rem: return BroopOverviewPalette.stageREM
        }
    }

    var broopTitle: String {
        switch self {
        case .awake: return String(localized: "Awake")
        case .light: return String(localized: "Light")
        case .deep: return String(localized: "SWS (Deep)")
        case .rem: return String(localized: "REM")
        }
    }

    func minutes(in s: Stages) -> Double {
        switch self {
        case .awake: return s.awake
        case .light: return s.light
        case .deep: return s.deep
        case .rem: return s.rem
        }
    }
}

/// A vertical line down the middle of its frame.
struct BroopOverviewVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

/// The HOURS OF SLEEP card: the night's asleep total against the 30-day typical, the sleeping heart-rate
/// line with dashed bed and wake rules, the four stage rows (share bar over a hatched track with the
/// typical range boxed, or the stage's timeline once a stage is picked), and restorative sleep.
struct BroopOverviewNightCard: View {
    let night: Night
    let asleepReading: BroopReading?
    let restorativeReading: BroopReading?
    let typicals: [SleepStage: BroopOverviewStageTypical]
    let hr: [HRBucket]

    @State private var selected: SleepStage?
    private let order: [SleepStage] = [.awake, .light, .deep, .rem]

    var body: some View {
        let s = night.stages
        let smoothed = Hypnogram.displaySmoothed(night.intervals.sorted { $0.start < $1.start }, minDuration: 90)
        let origin = smoothed.first?.start ?? 0
        let span = max(1, (smoothed.map(\.end).max() ?? Double(night.session.endTs - night.session.effectiveStartTs)) - origin)
        BroopOverviewCard {
            VStack(alignment: .leading, spacing: 0) {
                headline(s)
                chart(smoothed, origin: origin, span: span)
                    .frame(height: 150)
                    .padding(.top, 18)
                Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1).padding(.top, 14)
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(width: 12, height: 12)
                    BroopCaps(String(localized: "Typical range"), size: 10.5, color: BroopPalette.textSecondary)
                    Spacer()
                    BroopCaps(String(localized: "Duration"), size: 10.5, color: BroopPalette.textSecondary)
                    Text(verbatim: BroopFormat.duration(night.timeInBed))
                        .font(BroopType.number(16))
                        .foregroundStyle(BroopPalette.textPrimary)
                }
                .padding(.top, 16)
                VStack(spacing: 16) {
                    ForEach(order, id: \.self) { stage in
                        stageRow(stage, s: s, intervals: smoothed, origin: origin, span: span)
                    }
                }
                .padding(.top, 16)
                if let sel = selected {
                    stageInsight(sel, s: s).padding(.top, 14)
                }
                Rectangle().fill(BroopOverviewPalette.hairline).frame(height: 1).padding(.top, 16)
                restorative(s).padding(.top, 14)
            }
        }
        .onChange(of: night.session.effectiveStartTs) { _, _ in selected = nil }
    }

    // MARK: Headline

    @ViewBuilder
    private func headline(_ s: Stages) -> some View {
        if let sel = selected {
            let minutes = sel.minutes(in: s)
            let typ = typicals[sel]
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(sel.broopTitle, size: 11.5, color: sel.broopColor)
                    valueLine(BroopFormat.duration(minutes),
                              up: typ.map { minutes > $0.hi ? true : (minutes < $0.lo ? false : nil) } ?? nil,
                              good: sel != .awake)
                    if let typ {
                        Text(verbatim: BroopFormat.duration(typ.mean))
                            .font(BroopType.number(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                Spacer()
            }
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BroopCaps(String(localized: "Hours of Sleep"), size: 11.5)
                    valueLine(BroopFormat.duration(s.asleep), up: asleepReading?.trendSymbol.map { $0.contains("up") }, good: true)
                    if let base = asleepReading?.baseline {
                        Text(verbatim: BroopFormat.duration(base))
                            .font(BroopType.number(14))
                            .foregroundStyle(BroopPalette.textSecondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func valueLine(_ text: String, up: Bool?, good: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: text)
                .font(BroopType.number(32))
                .broopNumeral(32)
                .foregroundStyle(BroopPalette.textPrimary)
            if let up {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(up == good ? BroopOverviewPalette.optimal : BroopOverviewPalette.poor)
            }
        }
    }

    // MARK: Heart-rate chart

    /// The night's HR in steel blue with a soft fill, dashed rules at bed and wake. A picked stage washes
    /// its columns and redraws the line in the stage colour there. Breaks across gaps over five minutes.
    private func chart(_ intervals: [SleepInterval], origin: TimeInterval, span: TimeInterval) -> some View {
        let onset = TimeInterval(night.session.effectiveStartTs)
        let wake = TimeInterval(night.session.endTs)
        // A little of the evening and morning either side, as WHOOP draws it.
        let pad = max(600, (wake - onset) * 0.05)
        let lo0 = onset - pad, hi0 = wake + pad
        let buckets = hr.filter { TimeInterval($0.ts) >= lo0 && TimeInterval($0.ts) <= hi0 }
        let sel = selected
        let ranges: [(Double, Double)] = sel.map { st in
            intervals.filter { $0.stage == st }.map { (night.onsetDate.timeIntervalSince1970 + $0.start,
                                                        night.onsetDate.timeIntervalSince1970 + $0.end) }
        } ?? []
        return GeometryReader { geo in
            let axisW: CGFloat = 30
            let w = geo.size.width - axisW
            let h = geo.size.height - 22
            let bpms = buckets.map(\.bpm)
            let minB = ((bpms.min() ?? 50) - 5)
            let maxB = ((bpms.max() ?? 90) + 5)
            let lo = (minB / 20).rounded(.down) * 20
            let hi = max(lo + 40, (maxB / 20).rounded(.up) * 20)
            let x = { (t: TimeInterval) -> CGFloat in axisW + CGFloat((t - lo0) / max(1, hi0 - lo0)) * w }
            let y = { (b: Double) -> CGFloat in 8 + (h - 8) * (1 - CGFloat((b - lo) / max(1, hi - lo))) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Gridlines and labels every 20 bpm.
                    var g = lo
                    while g <= hi {
                        ctx.draw(Text(verbatim: "\(Int(g))").font(BroopType.number(11)).foregroundColor(BroopPalette.textSecondary),
                                 at: CGPoint(x: 12, y: y(g)))
                        g += 20
                    }
                    for (a, b) in ranges {
                        let rect = CGRect(x: x(a), y: 0, width: max(1, x(b) - x(a)), height: h)
                        ctx.fill(Path(rect), with: .color((sel?.broopColor ?? .clear).opacity(0.16)))
                    }
                    var line = Path(), fill = Path()
                    var prev: HRBucket?
                    var runStart: CGPoint?
                    func closeRun(at p: CGPoint?) {
                        guard let s = runStart, let p else { return }
                        fill.addLine(to: CGPoint(x: p.x, y: h))
                        fill.addLine(to: CGPoint(x: s.x, y: h))
                        fill.closeSubpath()
                    }
                    var last: CGPoint?
                    for b in buckets {
                        let p = CGPoint(x: x(TimeInterval(b.ts)), y: y(b.bpm))
                        if let pr = prev, b.ts - pr.ts <= 300 {
                            line.addLine(to: p); fill.addLine(to: p)
                        } else {
                            closeRun(at: last)
                            line.move(to: p); fill.move(to: p); runStart = p
                        }
                        prev = b; last = p
                    }
                    closeRun(at: last)
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [BroopPalette.rest.opacity(0.28), BroopPalette.rest.opacity(0)]),
                                                         startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                    ctx.stroke(line, with: .color(sel == nil ? BroopPalette.rest : BroopPalette.textTertiary),
                               style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    if let sel {
                        var over = Path()
                        var lastIn: Int?
                        for b in buckets {
                            let t = TimeInterval(b.ts)
                            guard ranges.contains(where: { t >= $0.0 && t <= $0.1 }) else { lastIn = nil; continue }
                            let p = CGPoint(x: x(t), y: y(b.bpm))
                            if let l = lastIn, b.ts - l <= 300 { over.addLine(to: p) } else { over.move(to: p) }
                            lastIn = b.ts
                        }
                        ctx.stroke(over, with: .color(sel.broopColor), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    }
                    for t in [onset, wake] {
                        var rule = Path()
                        rule.move(to: CGPoint(x: x(t), y: 0)); rule.addLine(to: CGPoint(x: x(t), y: h))
                        ctx.stroke(rule, with: .color(BroopPalette.textPrimary.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ctx.fill(Path(ellipseIn: CGRect(x: x(t) - 3, y: h - 3, width: 6, height: 6)), with: .color(BroopPalette.textPrimary))
                    }
                }
                if buckets.count < 2 {
                    Text("No heart-rate detail for this night")
                        .font(BroopType.medium(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .frame(width: geo.size.width, height: h)
                }
                Text(verbatim: BroopFormat.time(Date(timeIntervalSince1970: onset)))
                    .font(BroopType.demi(12.5))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize()
                    .position(x: max(34, x(onset) + 24), y: geo.size.height - 8)
                Text(verbatim: BroopFormat.time(Date(timeIntervalSince1970: wake)))
                    .font(BroopType.demi(12.5))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .fixedSize()
                    .position(x: min(geo.size.width - 30, x(wake) - 20), y: geo.size.height - 8)
            }
        }
        .accessibilityLabel(Text("Sleeping heart rate through the night"))
    }

    // MARK: Stage rows

    private func stageRow(_ stage: SleepStage, s: Stages, intervals: [SleepInterval],
                          origin: TimeInterval, span: TimeInterval) -> some View {
        let minutes = stage.minutes(in: s)
        let total = max(1, s.total)
        let pct = sharePercent(stage, s)
        let isSel = selected == stage
        let timeline = selected != nil
        let color = stage.broopColor
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selected = isSel ? nil : stage }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(BroopPalette.textPrimary, lineWidth: 2)
                        if isSel { Circle().fill(color).padding(5) }
                    }
                    .frame(width: 26, height: 26)
                    BroopCaps(stage.broopTitle, size: 11.5)
                    Text(verbatim: "\(pct)%")
                        .font(BroopType.demi(13))
                        .foregroundStyle(timeline && !isSel ? BroopPalette.textSecondary : color)
                    Spacer()
                    Text(verbatim: BroopFormat.duration(minutes))
                        .font(BroopType.number(18))
                        .broopNumeral(18)
                        .foregroundStyle(BroopPalette.textPrimary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        BroopOverviewHatch()
                        if timeline {
                            ForEach(intervals.filter { $0.stage == stage }) { iv in
                                Rectangle()
                                    .fill(isSel ? color : BroopPalette.textSecondary.opacity(0.55))
                                    .frame(width: max(1.5, CGFloat((iv.end - iv.start) / span) * w))
                                    .offset(x: CGFloat((iv.start - origin) / span) * w)
                            }
                        } else {
                            Rectangle()
                                .fill(color)
                                .frame(width: max(2, CGFloat(min(1, minutes / total)) * w))
                            if let typ = typicals[stage] {
                                let x0 = CGFloat(min(1, typ.lo / total)) * w
                                let x1 = CGFloat(min(1, typ.hi / total)) * w
                                Rectangle()
                                    .fill(Color.white.opacity(0.10))
                                    .overlay(
                                        HStack {
                                            dashed
                                            Spacer(minLength: 0)
                                            dashed
                                        }
                                    )
                                    .frame(width: max(6, x1 - x0))
                                    .padding(.vertical, -4)
                                    .offset(x: x0)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(height: geo.size.height)
                }
                .frame(height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(stage.broopTitle): \(BroopFormat.duration(minutes)), \(pct)%"))
        .accessibilityHint(Text("Shows when this stage happened"))
    }

    private var dashed: some View {
        BroopOverviewVLine()
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .frame(width: 1)
    }

    /// Largest-remainder whole percentages, the same apportionment the classic rows print.
    private func sharePercent(_ stage: SleepStage, _ s: Stages) -> Int {
        guard let p = StagePercentages.wholePercentages([s.awake, s.light, s.deep, s.rem]) else { return 0 }
        switch stage {
        case .awake: return p[0]
        case .light: return p[1]
        case .deep: return p[2]
        case .rem: return p[3]
        }
    }

    private func stageInsight(_ stage: SleepStage, s: Stages) -> some View {
        let minutes = stage.minutes(in: s)
        let text: String
        if let t = typicals[stage] {
            let phrase = minutes > t.hi ? String(localized: "more than") : (minutes < t.lo ? String(localized: "less than") : String(localized: "about the same as"))
            text = String(localized: "You spent \(BroopFormat.duration(minutes)) in \(stage.broopTitle), which is \(phrase) your 30-day typical of \(BroopFormat.duration(t.lo)) to \(BroopFormat.duration(t.hi)).")
        } else {
            text = String(localized: "You spent \(BroopFormat.duration(minutes)) in \(stage.broopTitle). A typical range appears after five scored nights.")
        }
        return Text(verbatim: text)
            .font(BroopType.medium(14))
            .foregroundStyle(BroopPalette.textBody)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func restorative(_ s: Stages) -> some View {
        HStack(spacing: 12) {
            LinearGradient(colors: [BroopOverviewPalette.stageDeep, BroopOverviewPalette.stageREM],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            BroopCaps(String(localized: "Restorative Sleep"), size: 11.5)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: BroopFormat.duration(s.deep + s.rem))
                        .font(BroopType.number(22))
                        .broopNumeral(22)
                        .foregroundStyle(BroopPalette.textPrimary)
                    if let r = restorativeReading, let sym = r.trendSymbol {
                        Image(systemName: sym).font(.system(size: 8)).foregroundStyle(r.trendTint)
                    }
                }
                if let base = restorativeReading?.baseline {
                    Text(verbatim: BroopFormat.duration(base))
                        .font(BroopType.number(13))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .padding(.trailing, 14)
                }
            }
        }
    }
}
#endif
