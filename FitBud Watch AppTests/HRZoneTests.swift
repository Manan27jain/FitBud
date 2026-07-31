import Testing
@testable import FitBud_Watch_App

struct HRZoneTests {
    @Test func tableCoversFiveZonesFrom133To207() {
        #expect(HRZone.table.count == 5)
        #expect(HRZone.table.map(\.id) == ["Z1", "Z2", "Z3", "Z4", "Z5"])
        #expect(HRZone.lowerBound == 133)
        #expect(HRZone.upperBound == 207)
    }

    @Test func zonesAreContiguousWithNoGapsOrOverlaps() {
        for (lower, upper) in zip(HRZone.table, HRZone.table.dropFirst()) {
            #expect(lower.upperBPM == upper.lowerBPM)
        }
    }

    @Test func theAthletesEasyZoneIs148To163() {
        let easy = HRZone.table[1]
        #expect(easy.id == "Z2")
        #expect(easy.name == "Easy")
        #expect(easy.lowerBPM == 148)
        #expect(easy.upperBPM == 163)
    }

    @Test func boundaryHeartRateBelongsToTheZoneItOpens() {
        // 148 is the first beat of Z2, not the last of Z1.
        #expect(HRZone.zone(for: 148)?.id == "Z2")
        #expect(HRZone.zone(for: 147)?.id == "Z1")
        #expect(HRZone.zone(for: 163)?.id == "Z3")
    }

    @Test func heartRatesInsideEachZoneClassifyCorrectly() {
        #expect(HRZone.zone(for: 140)?.id == "Z1")
        #expect(HRZone.zone(for: 155)?.id == "Z2")
        #expect(HRZone.zone(for: 170)?.id == "Z3")
        #expect(HRZone.zone(for: 185)?.id == "Z4")
        #expect(HRZone.zone(for: 200)?.id == "Z5")
    }

    @Test func heartRateAtOrAboveMaxSaturatesToTheTopZone() {
        // 207 is the observed max, and anything at or beyond it is still Z5
        // rather than falling off the end of the table.
        #expect(HRZone.zone(for: 207)?.id == "Z5")
        #expect(HRZone.zone(for: 240)?.id == "Z5")
    }

    @Test func heartRateBelowTheFirstZoneHasNoZone() {
        // Resting and walking heart rates are genuinely outside the training
        // zones; reporting Z1 for a resting 62 bpm would be a lie.
        #expect(HRZone.zone(for: 132) == nil)
        #expect(HRZone.zone(for: 60) == nil)
    }
}

#if DEBUG
struct DemoHeartRateScriptTests {
    @Test func theScriptedSweepVisitsEveryZone() {
        // If the demo never reaches Z5 the ring's red state can never be looked
        // at, and this task would not achieve what it exists for.
        var visited = Set<String>()
        for second in stride(from: 0.0, through: 1_200.0, by: 5.0) {
            let bpm = DemoWorkoutRecorder.scriptedHeartRate(at: second)
            if let zone = HRZone.zone(for: bpm) { visited.insert(zone.id) }
        }
        #expect(visited == ["Z1", "Z2", "Z3", "Z4", "Z5"])
    }
}
#endif
