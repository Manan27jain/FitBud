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

    // MARK: - zonePercentages

    @Test func noSharesYieldsNoPercentages() {
        #expect(zonePercentages([]).isEmpty)
    }

    @Test func aSingleZoneIsExactlyOneHundredPercent() {
        let shares = zoneShares(timeInZone: ["Z2": 1_800])
        #expect(zonePercentages(shares) == [100])
    }

    @Test func twoEvenZonesSplitFiftyFifty() {
        let shares = zoneShares(timeInZone: ["Z1": 600, "Z2": 600])
        #expect(zonePercentages(shares) == [50, 50])
    }

    /// The bug this test exists to catch: rounding each share independently
    /// gives 33/33/33 = 99, not 100. Three exactly-equal thirds must still
    /// sum to 100 on screen.
    @Test func threeEqualThirdsSumToOneHundredNotNinetyNine() {
        let shares = zoneShares(timeInZone: ["Z1": 100, "Z2": 100, "Z3": 100])
        let percentages = zonePercentages(shares)
        #expect(percentages.reduce(0, +) == 100)
        // Two of the three round down to 33, one takes the leftover point.
        #expect(Set(percentages) == [33, 34])
    }

    @Test func aLopsidedSplitStillSumsToOneHundred() {
        let shares = zoneShares(timeInZone: ["Z1": 1, "Z2": 999])
        let percentages = zonePercentages(shares)
        #expect(percentages.reduce(0, +) == 100)
        // 1/1000 of the time rounds away entirely; the dominant zone gets the
        // rest rather than the leftover point going to the near-zero share.
        #expect(percentages == [0, 100])
    }

    /// Percentages must line up positionally with the `shares` they were
    /// computed from, in zone order, not just sum correctly in aggregate.
    @Test func percentagesAlignPositionallyWithShares() {
        let shares = zoneShares(timeInZone: ["Z1": 20, "Z3": 30, "Z5": 50])
        let percentages = zonePercentages(shares)
        #expect(shares.map(\.zone.id) == ["Z1", "Z3", "Z5"])
        #expect(percentages == [20, 30, 50])
    }
}
