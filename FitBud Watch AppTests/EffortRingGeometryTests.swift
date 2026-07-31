import Testing
@testable import FitBud_Watch_App

struct EffortRingGeometryTests {
    @Test func arcSpans240DegreesLeavingAGapAtTheBottom() {
        #expect(EffortRingGeometry.startAngle == 150)
        #expect(EffortRingGeometry.sweep == 240)
        #expect(EffortRingGeometry.endAngle == 390)
    }

    @Test func lowestTrainingHeartRateSitsAtTheStartOfTheArc() {
        #expect(EffortRingGeometry.angle(forHeartRate: 133) == 150)
    }

    @Test func maximumHeartRateSitsAtTheEndOfTheArc() {
        #expect(EffortRingGeometry.angle(forHeartRate: 207) == 390)
    }

    @Test func midRangeHeartRateSitsHalfwayAround() {
        // 170 is 37 of the 74 bpm span, so exactly half of 240 degrees.
        #expect(abs(EffortRingGeometry.angle(forHeartRate: 170) - 270) < 0.001)
    }

    @Test func heartRatesOutsideTheRangeClampInsteadOfWrapping() {
        // Wrapping would put the needle inside the bottom gap, where it would
        // read as a completely different effort.
        #expect(EffortRingGeometry.angle(forHeartRate: 60) == 150)
        #expect(EffortRingGeometry.angle(forHeartRate: 250) == 390)
    }

    @Test func eachZonesArcMatchesItsShareOfTheHeartRateRange() {
        let easy = HRZone.table[1] // Z2, 148-163
        let arc = EffortRingGeometry.arc(for: easy)
        #expect(abs(arc.start - (150 + (15.0 / 74.0) * 240)) < 0.001)
        #expect(abs(arc.end - (150 + (30.0 / 74.0) * 240)) < 0.001)
    }

    @Test func zoneArcsAreContiguousAndFillTheWholeSweep() {
        let arcs = HRZone.table.map(EffortRingGeometry.arc(for:))
        #expect(abs(arcs[0].start - 150) < 0.001)
        #expect(abs(arcs[arcs.count - 1].end - 390) < 0.001)
        for (lower, upper) in zip(arcs, arcs.dropFirst()) {
            #expect(abs(lower.end - upper.start) < 0.001)
        }
    }
}
