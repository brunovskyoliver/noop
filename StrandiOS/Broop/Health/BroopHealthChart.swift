#if os(iOS)
import Charts
import SwiftUI
import StrandDesign

/// One plotted day (or bucket).
struct BroopHealthPoint: Identifiable, Equatable {
    let day: String
    let date: Date
    let value: Double
    var segment: String = "a"
    var id: String { day + segment }
}

/// The WHOOP Trend View chart: bars (sums/counts) or a line with open-circle markers (scores and
/// physiology), a lighter typical-range band, a dashed average rule with an "AVG." pill, grey y labels
/// on the left and two-line date ticks. Press-and-drag selects a point; the parent shows the readout.
struct BroopHealthTrendChart: View {
    enum Style { case bars, line }

    let points: [BroopHealthPoint]
    let style: Style
    var yDomain: ClosedRange<Double>
    var typical: ClosedRange<Double>? = nil
    var average: Double? = nil
    var color: (Double) -> Color = { _ in BroopHealthPalette.chartBlue }
    var valueLabel: (Double) -> String = { BroopFormat.whole($0) }
    var axisLabel: (Double) -> String = { BroopFormat.whole($0) }
    /// Label every marker (week view).
    var labelsPoints = false
    @Binding var selection: BroopHealthPoint?
    var height: CGFloat = 250

    var body: some View {
        Chart {
            if let typical {
                RectangleMark(xStart: nil, xEnd: nil,
                              yStart: .value("Low", typical.lowerBound), yEnd: .value("High", typical.upperBound))
                    .foregroundStyle(BroopHealthPalette.typicalBand)
            }
            ForEach(points) { p in
                switch style {
                case .bars:
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value), width: .ratio(0.6))
                        .foregroundStyle(color(p.value).opacity(selection == nil || selection == p ? 1 : 0.45))
                case .line:
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value),
                             series: .value("Segment", p.segment))
                        .foregroundStyle(BroopHealthPalette.chartBlue.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    if showsMarkers {
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value("Value", p.value))
                            .symbol { marker(p) }
                            .annotation(position: .top, spacing: 2) {
                                if labelsPoints {
                                    Text(verbatim: valueLabel(p.value))
                                        .font(BroopType.number(13))
                                        .foregroundStyle(BroopHealthPalette.chartBlue)
                                        .padding(.horizontal, 3)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(broopHex: 0x14191D)))
                                }
                            }
                    }
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .annotation(position: .overlay, alignment: .leading) {
                        Text("AVG.")
                            .font(BroopType.caps(9.5))
                            .tracking(0.8)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    }
            }
            if let selection {
                RuleMark(x: .value("Selected", selection.date, unit: .day))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if style == .line {
                    PointMark(x: .value("Day", selection.date, unit: .day), y: .value("Value", selection.value))
                        .symbolSize(90)
                        .foregroundStyle(.white)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(BroopHealthPalette.grid)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(verbatim: axisLabel(v)).font(BroopType.number(12)).foregroundStyle(BroopPalette.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xTickCount)) { value in
                AxisValueLabel(centered: false) {
                    if let d = value.as(Date.self) {
                        VStack(spacing: 1) {
                            Text(d, format: xTopFormat)
                            Text(d, format: xBottomFormat)
                        }
                        .font(BroopType.medium(12))
                        .foregroundStyle(BroopPalette.textSecondary)
                        .fixedSize()
                        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard let plot = proxy.plotFrame else { return }
                                let x = g.location.x - geo[plot].origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                let nearest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                                if nearest != selection { selection = nearest }
                            }
                            .onEnded { _ in selection = nil }
                    )
            }
        }
        .frame(height: height)
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    }

    private var span: TimeInterval {
        guard let a = points.first?.date, let b = points.last?.date else { return 0 }
        return b.timeIntervalSince(a)
    }
    private var showsMarkers: Bool { points.count <= 14 }
    private var xTickCount: Int { points.count <= 8 ? max(points.count, 2) : 5 }
    private var xTopFormat: Date.FormatStyle {
        span <= 8 * 86_400 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated)
    }
    private var xBottomFormat: Date.FormatStyle {
        span > 200 * 86_400 ? .dateTime.year(.twoDigits) : .dateTime.day()
    }

    private func marker(_ p: BroopHealthPoint) -> some View {
        Circle()
            .strokeBorder(BroopHealthPalette.chartBlue, lineWidth: 2)
            .background(Circle().fill(Color(broopHex: 0x14191D)))
            .frame(width: 11, height: 11)
    }
}

/// W | M | 6M plus a caps menu for the other trailing windows (2W, 3W, 3M, 1Y, ALL), so every range the
/// classic control offered stays one tap away without crowding WHOOP's three-way switch.
struct BroopHealthRangePicker: View {
    @Binding var selection: ExploreRange
    var isEnabled: (ExploreRange) -> Bool = { _ in true }
    var primary: [ExploreRange] = [.week, .month, .half]

    var body: some View {
        HStack(spacing: 8) {
            BroopHealthSegmented(options: primary, selection: primaryBinding, isEnabled: isEnabled) { $0.label }
            Menu {
                ForEach(ExploreRange.allCases) { r in
                    Button {
                        selection = r
                    } label: {
                        if r == selection { Label(r.label, systemImage: "checkmark") } else { Text(verbatim: r.label) }
                    }
                    .disabled(!isEnabled(r))
                }
            } label: {
                Text(verbatim: primary.contains(selection) ? "•••" : selection.label)
                    .font(BroopType.caps(12))
                    .tracking(0.6)
                    .foregroundStyle(primary.contains(selection) ? BroopPalette.textSecondary : BroopPalette.textPrimary)
                    .frame(minWidth: 44)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(primary.contains(selection) ? BroopHealthPalette.segTrack : BroopHealthPalette.segSelected))
            }
            .accessibilityLabel(Text("More ranges"))
        }
    }

    /// A non-primary selection highlights nothing in the three-way switch.
    private var primaryBinding: Binding<ExploreRange> {
        Binding(get: { selection }, set: { selection = $0 })
    }
}
#endif
