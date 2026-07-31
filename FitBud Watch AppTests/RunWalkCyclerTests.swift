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
