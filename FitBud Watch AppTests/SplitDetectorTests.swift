import Testing
@testable import FitBud_Watch_App

struct SplitPaceTests {
    @Test func paceIsSecondsPerKilometre() {
        let split = Split(
            index: 1,
            distanceMeters: 1000,
            elapsed: 540,
            duration: 540,
            averageHeartRate: 155
        )
        #expect(split.paceSecPerKm == 540)
    }

    @Test func paceIsZeroForZeroDistance() {
        let split = Split(index: 1, distanceMeters: 0, elapsed: 10, duration: 10, averageHeartRate: nil)
        #expect(split.paceSecPerKm == 0)
    }
}
