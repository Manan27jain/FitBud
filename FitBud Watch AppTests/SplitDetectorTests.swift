import Testing
@testable import FitBud_Watch_App

struct SplitPaceTests {
    @Test func paceIsSecondsPerKilometre() {
        let split = Split(
            index: 1,
            distanceMeters: 1000,
            elapsed: 540,
            duration: 540,
            heartRateAtSplit: 155
        )
        #expect(split.paceSecPerKm == 540)
    }

    @Test func paceIsZeroForZeroDistance() {
        let split = Split(index: 1, distanceMeters: 0, elapsed: 10, duration: 10, heartRateAtSplit: nil)
        #expect(split.paceSecPerKm == 0)
    }
}

struct SplitDetectorTests {
    @Test func noSplitBeforeFirstKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        #expect(detector.update(distanceMeters: 999, elapsed: 500, heartRate: 150).isEmpty)
        #expect(detector.splits.isEmpty)
    }

    @Test func splitFiresAtExactlyOneKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        #expect(splits.count == 1)
        #expect(splits[0].index == 1)
        #expect(splits[0].duration == 540)
        #expect(splits[0].elapsed == 540)
    }

    @Test func splitDurationIsTimeSinceTheLastSplit() {
        var detector = SplitDetector(intervalMeters: 1000)
        _ = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        let second = detector.update(distanceMeters: 2000, elapsed: 1100, heartRate: 158)
        #expect(second.count == 1)
        #expect(second[0].index == 2)
        #expect(second[0].duration == 560)
        #expect(second[0].elapsed == 1100)
    }

    @Test func splitDoesNotRepeatWhileInsideTheSameKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        _ = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        #expect(detector.update(distanceMeters: 1400, elapsed: 760, heartRate: 152).isEmpty)
        #expect(detector.splits.count == 1)
    }

    @Test func aDistanceJumpEmitsEverySplitItCrossed() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 2100, elapsed: 1100, heartRate: 150)
        #expect(splits.count == 2)
        #expect(splits.map(\.index) == [1, 2])
        #expect(detector.splits.count == 2)
    }

    @Test func heartRateIsCarriedOntoTheSplit() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 162)
        #expect(splits[0].heartRateAtSplit == 162)
    }
}
