import XCTest
@testable import Strand

/// The body clock dial's radial bands may not overlap (#2350).
///
/// The reported symptom was that the "your clock" arc read as radial hash marks running into the six-hour
/// ticks. Two separate causes: the arc was stroked at the SAME radius the ticks occupy, and its dashes
/// were shorter than the stroke was wide, so each one rendered as a stubby rectangle pointing outwards.
///
/// Neither is catchable by compiling, and neither is visible in a unit test either. What IS checkable is
/// the arithmetic: given the named radii and widths, no two bands may share space, and a dash must be
/// longer than its stroke is wide. That is the part of "does this look right" a test can honestly own.
/// Whether the result READS well still needs eyes on a device.
///
/// Twin of the Kotlin `BodyClockDialLayoutTest`, same numbers, since the two dials are drawn to one spec.
final class BodyClockDialLayoutTests: XCTestCase {

    /// A band is the radial span a drawn element occupies, from the dial centre outwards.
    private struct Band {
        let name: String
        let from: Double
        let to: Double
    }

    private let tunedRim = 90.0         // side/2 - 10 at the card's 200 pt height
    private let midnightTick = 6.0
    private let labelHeight = 11.0      // caption numerals, generously rounded up
    private let referenceWidth = 7.0
    private let nightWidth = 9.0
    private let glyph = 12.0

    /// Mirrors `DialGeometry`: the offsets are a fraction of the radius, so the bands scale with it.
    private func bands(rim: Double) -> [Band] {
        let k = rim / tunedRim
        return [
            Band(name: "ticks", from: rim - midnightTick * k, to: rim),
            Band(name: "labels",
                 from: (rim - 15 * k) - labelHeight * k / 2, to: (rim - 15 * k) + labelHeight * k / 2),
            Band(name: "reference arc",
                 from: (rim - 31 * k) - referenceWidth * k / 2, to: (rim - 31 * k) + referenceWidth * k / 2),
            Band(name: "night arc",
                 from: (rim - 45 * k) - nightWidth * k / 2, to: (rim - 45 * k) + nightWidth * k / 2),
            Band(name: "bed glyph",
                 from: (rim - 58 * k) - glyph * k / 2, to: (rim - 58 * k) + glyph * k / 2),
        ]
    }

    /// Rims a real card can actually be handed, from a narrow split pane up to the tuned size.
    private let rimsToCheck = [15.0, 25.0, 40.0, 50.0, 70.0, 90.0]

    func testNoTwoBandsOverlapAtAnySize() {
        for rim in rimsToCheck {
            let ordered = bands(rim: rim)
            for (outerBand, innerBand) in zip(ordered, ordered.dropFirst()) {
                let gap = outerBand.from - innerBand.to
                XCTAssertGreaterThan(
                    gap, 0,
                    "at rim \(rim), \(innerBand.name) runs into \(outerBand.name): gap is \(gap)")
            }
        }
    }

    /// The innermost element must clear the centre AT EVERY SIZE, not only the tuned one.
    ///
    /// With fixed offsets the nesting depth stayed 58 pt however small the card got, so a narrow one
    /// drove the bed through the centre and the night arc to a negative radius, which is undefined for
    /// `addArc` and draws nothing in the Kotlin twin. Checking a single rim asserted the design was
    /// sound at one size and said nothing about the range, which is the shape of test that lets it by.
    func testTheInnermostBandClearsTheCentreAtAnySize() {
        for rim in rimsToCheck {
            let innermost = bands(rim: rim)[bands(rim: rim).count - 1]
            XCTAssertGreaterThan(
                innermost.from, 0,
                "at rim \(rim), \(innermost.name) reaches the centre (from \(innermost.from))")
        }
    }

    /// A dash shorter than the stroke is wide is not a dash, it is a hash mark pointing outwards. The
    /// first attempt at this dial used a 3 pt dash under a 7 pt stroke; an earlier one used a round cap,
    /// which adds width/2 of ink at EACH end of EVERY dash and closed the gaps entirely. The invariant
    /// that survives both is simply that the dash must be the longer of the two.
    func testTheReferenceDashIsLongerThanItIsWide() {
        let dashLength = 10.0
        XCTAssertGreaterThan(
            dashLength, referenceWidth,
            "a \(dashLength) pt dash under a \(referenceWidth) pt stroke reads as a hash mark")
    }

    /// The bed marks onset, so it must sit off the night arc rather than on top of the end it marks.
    func testTheBedGlyphSitsOffTheNightArc() {
        for rim in rimsToCheck {
            let night = bands(rim: rim).first { $0.name == "night arc" }!
            let bed = bands(rim: rim).first { $0.name == "bed glyph" }!
            XCTAssertLessThan(bed.to, night.from, "at rim \(rim) the bed overlaps the arc it marks")
        }
    }
}
