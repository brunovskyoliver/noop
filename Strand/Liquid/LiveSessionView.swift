//  LiveSessionView.swift
//  NOOP · Live Sessions (silent guardian) — the in-session screen + summary sheet.
//
//  Deliberately near-empty: one breathing ring, one line of intent, one honest Charge
//  sentence that fades, an End button. The ring is the whole language — lit teal and
//  breathing in band, dimmed below, hot above, grey when the stream is stale (coaching
//  paused, nothing claimed). NO live HR number by default; a long-press on the ring
//  reveals the engine's smoothed bpm. A thin outer arc fills with time held in band,
//  toward an hour. Every value on screen is the engine's `Output`, verbatim — this
//  file renders, it never decides.
//
//  Design contract: docs/superpowers/specs/2026-07-04-live-sessions-design.md.

import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Summary sheet

/// The end-of-session read-out: time in / below / above the band, the cues sent, a plain verdict, and
/// the streak line. Everything comes off the banked `LiveSessionRow` — the same record the look-back
/// reads, so this sheet and history can never disagree.
struct LiveSessionSummarySheet: View {
    let row: LiveSessionRow
    let guardedCount: Int?
    let onDone: () -> Void
    @AppStorage(CardAppearancePrefs.opacityKey) private var cardOpacityPercent = CardAppearancePrefs.defaultPercent
    private var cardOpacity: Double { max(0, min(1, Double(cardOpacityPercent) / 100)) }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE SESSION")
                    .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.metricCyan)
                Text("Session summary")
                    .font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
            }
            .padding(.top, NoopMetrics.space6)

            Text(Self.verdict(row: row))
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            summaryCard {
                bandRow(String(localized: "In band"), seconds: row.inBandSec, tint: StrandPalette.metricCyan)
                bandRow(String(localized: "Below band"), seconds: row.belowSec, tint: StrandPalette.textTertiary)
                bandRow(String(localized: "Above band"), seconds: row.aboveSec, tint: StrandPalette.statusCritical)
            }

            summaryCard {
                HStack {
                    Text("Cues sent").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text(cueLine).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                }
                HStack {
                    Text("Band").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    Text("\(Int(row.floorBpm.rounded()))–\(Int(row.ceilingBpm.rounded())) bpm")
                        .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                }
            }

            if let n = guardedCount, n > 0 {
                Text(n == 1 ? String(localized: "1 session guarded")
                            : String(localized: "\(n) sessions guarded"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: NoopMetrics.space3)
            NoopButton("Done", kind: .primary, fullWidth: true) { onDone() }
        }
        .screenPadding()
        .padding(.vertical, NoopMetrics.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
    }

    // MARK: Rows

    private func bandRow(_ label: String, seconds: Double, tint: Color) -> some View {
        HStack(spacing: NoopMetrics.rowSpacing) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Text(Self.clock(seconds))
                .font(StrandFont.number(17)).monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func summaryCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: 22, surfaceOpacity: cardOpacity))
    }

    private var cueLine: String {
        if row.pushCount == 0 && row.easeCount == 0 {
            return String(localized: "None — silence, start to finish")
        }
        var parts: [String] = []
        if row.pushCount > 0 { parts.append(String(localized: "\(row.pushCount) push")) }
        if row.easeCount > 0 { parts.append(String(localized: "\(row.easeCount) ease-off")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Verdict (pure + honest — fractions of the banked totals, no editorialising beyond them)

    static func verdict(row: LiveSessionRow) -> String {
        let total = row.inBandSec + row.belowSec + row.aboveSec
        guard total >= 300 else {
            return String(localized: "Too short to judge — the band needs a few minutes to mean anything.")
        }
        let inFrac = row.inBandSec / total
        if inFrac >= 0.7 {
            return String(localized: "You held the band. Right where today wanted you.")
        }
        if inFrac >= 0.4 {
            return String(localized: "In and out, but the band won more than it lost.")
        }
        return row.belowSec >= row.aboveSec
            ? String(localized: "Mostly under the band — there was more in the tank today.")
            : String(localized: "Mostly over the band — harder than today's Charge could pay for.")
    }

    /// m:ss off the banked seconds (sessions are an hour-scale affair; no hour arithmetic needed).
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
