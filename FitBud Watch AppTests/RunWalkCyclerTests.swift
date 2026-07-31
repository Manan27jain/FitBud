import Testing
@testable import FitBud_Watch_App

struct RunWalkCyclerTests {
    let fourToOne = RunWalkCycler(runSeconds: 240, walkSeconds: 60)

    @Test func startsRunning() {
        #expect(fourToOne.phase(at: 0) == .run)
    }

    @Test func stillRunningJustBeforeTheSwitch() {
        #expect(fourToOne.phase(at: 239) == .run)
    }

    @Test func walksAtTheEndOfTheRunInterval() {
        #expect(fourToOne.phase(at: 240) == .walk)
    }

    @Test func returnsToRunningAtTheEndOfTheCycle() {
        #expect(fourToOne.phase(at: 300) == .run)
    }

    @Test func cyclesRepeatedly() {
        // Fourth cycle: 900s in is a run, 1140s in is a walk.
        #expect(fourToOne.phase(at: 900) == .run)
        #expect(fourToOne.phase(at: 1140) == .walk)
    }

    @Test func reportsTimeLeftInTheCurrentPhase() {
        #expect(fourToOne.remainingInPhase(at: 0) == 240)
        #expect(fourToOne.remainingInPhase(at: 100) == 140)
        #expect(fourToOne.remainingInPhase(at: 240) == 60)
        #expect(fourToOne.remainingInPhase(at: 280) == 20)
    }

    @Test func fiveToOneRatioUsedFromWeekFive() {
        let fiveToOne = RunWalkCycler(runSeconds: 300, walkSeconds: 60)
        #expect(fiveToOne.phase(at: 299) == .run)
        #expect(fiveToOne.phase(at: 300) == .walk)
        #expect(fiveToOne.phase(at: 360) == .run)
    }
}

struct RunWalkRemainingFractionTests {
    let fourToOne = RunWalkCycler(runSeconds: 240, walkSeconds: 60)

    @Test func startsFullAtTheBeginningOfARunInterval() {
        #expect(fourToOne.remainingFraction(at: 0) == 1.0)
    }

    @Test func drainsProportionallyThroughTheRunInterval() {
        #expect(abs(fourToOne.remainingFraction(at: 120) - 0.5) < 0.001)
        #expect(abs(fourToOne.remainingFraction(at: 180) - 0.25) < 0.001)
    }

    @Test func refillsWhenTheWalkBreakBegins() {
        // The fraction is of the *current* phase, so it resets to full at the
        // boundary rather than continuing to fall.
        #expect(fourToOne.remainingFraction(at: 240) == 1.0)
    }

    @Test func drainsProportionallyThroughTheWalkInterval() {
        #expect(abs(fourToOne.remainingFraction(at: 270) - 0.5) < 0.001)
    }

    @Test func staysWithinZeroAndOneAcrossAWholeCycle() {
        for second in stride(from: 0.0, through: 600.0, by: 0.5) {
            let fraction = fourToOne.remainingFraction(at: second)
            #expect(fraction >= 0)
            #expect(fraction <= 1)
        }
    }

    @Test func isUnaffectedByAJumpInElapsedTime() {
        // Statelessness check: a delayed or dropped sample must not desynchronise
        // the fraction, because it is recomputed from the clock every time.
        #expect(fourToOne.remainingFraction(at: 1_200) == 1.0)
        #expect(abs(fourToOne.remainingFraction(at: 1_320) - 0.5) < 0.001)
    }
}
