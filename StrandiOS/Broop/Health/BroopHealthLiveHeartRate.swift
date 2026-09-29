#if os(iOS)
import SwiftUI
import StrandDesign

/// The HEART RATE hero of the Health tab and Health Monitor: caps label, heart, big BPM, zone line and
/// zone meter on the left; a live trace fading in from the left and ending on a dot at a dashed "now"
/// line. Its own view so the ~1 Hz live stream re-renders only this subtree.
///
/// The value is the classic Health hero's `displayHR` (spike-filtered median, then the reported value,
/// then R-R derived) and the zone is the classic %HR-max band, so both screens read the same number.
struct BroopHealthLiveHeartRate: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var profile: ProfileStore

    /// Rolling 3-minute buffer, sampled on a fixed 1 Hz clock (the classic hero's #941 rule).
    @State private var samples: [Double] = []

    private var displayHR: Int? {
        if let hr = model.bpm, hr > 0 { return hr }
        if let hr = live.heartRate, hr > 0 { return hr }
        if let last = live.rr.last, last > 0 { return Int((60_000.0 / Double(last)).rounded()) }
        return nil
    }

    private func zone(_ hr: Int) -> Int {
        guard profile.hrMax > 0 else { return 1 }
        switch Double(hr) / Double(profile.hrMax) {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    var body: some View {
        let hr = displayHR
        let z = hr.map(zone)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BroopCaps(String(localized: "Heart Rate"), size: 13)
                Image(systemName: "heart.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(hr == nil ? BroopPalette.textSecondary : BroopHealthPalette.liveBlue)
                    .padding(.top, 12)
                Text(verbatim: hr.map(String.init) ?? "--")
                    .font(BroopType.number(40))
                    .foregroundStyle(BroopPalette.textPrimary)
                    .broopNumeral(40)
                    .padding(.top, 6)
                    .contentTransition(.numericText())
                BroopCaps("BPM", size: 11, color: BroopPalette.textSecondary)
                    .padding(.top, 2)
                Text(verbatim: statusLine(hr: hr, zone: z))
                    .font(BroopType.medium(15))
                    .foregroundStyle(BroopPalette.textBody)
                    .padding(.top, 12)
                zoneMeter(z).padding(.top, 10)
            }
            .frame(width: 118, alignment: .leading)
            BroopHealthLiveTrace(samples: samples, hasValue: hr != nil)
                .frame(maxWidth: .infinity)
                .frame(height: 138)
                .padding(.top, 2)
        }
        .padding(.horizontal, BroopMetrics.page + 8)
        .padding(.vertical, 22)
        .background(BroopHealthGrid().opacity(0.9))
        // A 1 Hz clock owned by the view's lifetime (a Timer publisher stored on the struct is rebuilt,
        // and resubscribed, every time a parent re-creates this view).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let v = displayHR, (30...220).contains(v) else { continue }
                samples.append(Double(v))
                if samples.count > 180 { samples.removeFirst(samples.count - 180) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: hr.map { String(localized: "Heart rate \($0) beats per minute") }
                                 ?? String(localized: "Heart rate not available")))
    }

    private func statusLine(hr: Int?, zone: Int?) -> String {
        if let zone, hr != nil { return String(localized: "Zone \(zone)") }
        if live.connected { return String(localized: "Calibrating...") }
        return String(localized: "Not connected")
    }

    private func zoneMeter(_ zone: Int?) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(zone == i ? BroopHealthPalette.zone(i) : Color(broopHex: 0x31393C))
                    .frame(width: 20, height: 3)
            }
        }
    }
}

/// The trace: a blue line with a soft fill, fading in from the left, a dashed now-line and a dot.
private struct BroopHealthLiveTrace: View {
    let samples: [Double]
    let hasValue: Bool

    var body: some View {
        Canvas { ctx, size in
            let nowX = size.width - 6
            // Dashed now-line.
            var dash = Path()
            dash.move(to: CGPoint(x: nowX, y: 0))
            dash.addLine(to: CGPoint(x: nowX, y: size.height))
            ctx.stroke(dash, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            guard hasValue, let lo0 = samples.min(), let hi0 = samples.max() else {
                let dot = CGRect(x: nowX - 6, y: 8, width: 12, height: 12)
                ctx.fill(Path(ellipseIn: dot), with: .color(.white))
                return
            }
            let span = max(hi0 - lo0, 16)
            let mid = (hi0 + lo0) / 2
            let lo = mid - span * 0.75, hi = mid + span * 0.75
            func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / (hi - lo)) }
            // Newest at the now-line; one sample per 1/180 of the width.
            let step = (nowX - 4) / 179
            let pts: [CGPoint] = samples.enumerated().map { i, v in
                CGPoint(x: nowX - CGFloat(samples.count - 1 - i) * step, y: y(v))
            }
            var line = Path()
            if pts.count == 1 {
                line.move(to: CGPoint(x: nowX - 40, y: pts[0].y))
                line.addLine(to: pts[0])
            } else {
                line.addLines(pts)
            }
            let startX = line.boundingRect.minX
            var area = line
            area.addLine(to: CGPoint(x: nowX, y: size.height))
            area.addLine(to: CGPoint(x: startX, y: size.height))
            area.closeSubpath()
            let fade = Gradient(stops: [.init(color: .clear, location: 0),
                                        .init(color: .white, location: 0.35)])
            ctx.drawLayer { layer in
                layer.fill(area, with: .linearGradient(
                    Gradient(colors: [BroopHealthPalette.liveBlue.opacity(0.28), BroopHealthPalette.liveBlue.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: line.boundingRect.minY), endPoint: CGPoint(x: 0, y: size.height)))
                layer.stroke(line, with: .color(BroopHealthPalette.liveBlue),
                             style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                layer.blendMode = .destinationIn
                layer.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .linearGradient(fade, startPoint: CGPoint(x: startX, y: 0),
                                                 endPoint: CGPoint(x: nowX, y: 0)))
            }
            if let last = pts.last {
                let outer = CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: outer), with: .color(Color(broopHex: 0x1B2227)))
                let inner = outer.insetBy(dx: 2.5, dy: 2.5)
                ctx.fill(Path(ellipseIn: inner), with: .color(.white))
            }
        }
    }
}

/// Faint square grid behind the heart-rate hero.
struct BroopHealthGrid: View {
    var spacing: CGFloat = 22

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            ctx.stroke(p, with: .color(.white.opacity(0.045)), lineWidth: 1)
        }
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
