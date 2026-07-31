import Testing
@testable import FitBud_Watch_App

struct ZoneBreakdownTests {
    @Test func noRecordedTimeYieldsNoShares() {
        #expect(zoneShares(timeInZone: [:]).isEmpty)
    }

    @Test func sharesAreProportionalAndSumToOne() {
        let shares = zoneShares(timeInZone: ["Z2": 3_600, "Z3": 1_200])
        #expect(shares.count == 2)
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1.0) < 0.0001)
        let easy = shares.first { $0.zone.id == "Z2" }
        #expect(abs((easy?.fraction ?? 0) - 0.75) < 0.0001)
    }

    @Test func sharesComeBackInZoneOrderNotDictionaryOrder() {
        let shares = zoneShares(timeInZone: ["Z5": 60, "Z1": 60, "Z3": 60])
        #expect(shares.map(\.zone.id) == ["Z1", "Z3", "Z5"])
    }

    @Test func zonesWithNoTimeAreOmitted() {
        // A run entirely in Z2 should render one solid bar, not five with four
        // of them zero-width.
        let shares = zoneShares(timeInZone: ["Z2": 1_800])
        #expect(shares.count == 1)
        #expect(shares[0].fraction == 1.0)
        #expect(shares[0].seconds == 1_800)
    }
}
