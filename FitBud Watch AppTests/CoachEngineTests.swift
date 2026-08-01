import Foundation
import Testing
@testable import FitBud_Watch_App

struct CoachEngineTests {
    private func state(
        elapsed: TimeInterval,
        hr: Double? = nil,
        km: Double = 0,
        phase: RunWalkPhase? = .run
    ) -> WorkoutState {
        var s = WorkoutState()
        s.elapsed = elapsed
        s.heartRate = hr
        s.currentZone = hr.flatMap(HRZone.zone(for:))
        s.distanceMeters = km * 1000
        s.runWalkPhase = phase
        return s
    }

    private func engine(_ rules: [CueRule], targetKm: Double = 10) -> CoachEngine {
        CoachEngine(brief: SessionBrief(opening: "Go", rules: rules), targetDistanceKm: targetKm)
    }

    // MARK: Trigger matching

    @Test func zoneAboveNeedsTheDriftSustained() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 30),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        // 175 is Z3 — above the Z2 ceiling — but only for a moment at first.
        #expect(e.evaluate(state: state(elapsed: 100, hr: 175), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 120, hr: 175), events: []) == nil)
        // 30s sustained: now it fires.
        #expect(e.evaluate(state: state(elapsed: 131, hr: 175), events: [])?.message == "Ease off.")
    }

    @Test func droppingBackIntoZoneResetsTheDriftClock() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 30),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        _ = e.evaluate(state: state(elapsed: 100, hr: 175), events: [])
        // Back into Z2 at 120 — the clock restarts, so 131 is only 11s of drift.
        _ = e.evaluate(state: state(elapsed: 120, hr: 155), events: [])
        _ = e.evaluate(state: state(elapsed: 125, hr: 175), events: [])
        #expect(e.evaluate(state: state(elapsed: 131, hr: 175), events: []) == nil)
    }

    @Test func splitTriggerFiresOnTheSplitEvent() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil),
                                message: "Another one.", repeats: true)])
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 540, duration: 540, heartRateAtSplit: 150)
        let cue = e.evaluate(state: state(elapsed: 540, hr: 150, km: 1, phase: .walk),
                             events: [.splitCompleted(split)])
        #expect(cue?.message == "Another one.")
    }

    @Test func anIndexedSplitTriggerIgnoresOtherSplits() {
        var e = engine([CueRule(trigger: .splitCompleted(index: 3), message: "Three.", repeats: false)])
        let first = Split(index: 1, distanceMeters: 1000, elapsed: 540, duration: 540, heartRateAtSplit: 150)
        #expect(e.evaluate(state: state(elapsed: 540, phase: .walk), events: [.splitCompleted(first)]) == nil)
    }

    @Test func halfwayUsesTheSessionTarget() {
        var e = engine([CueRule(trigger: .halfway, message: "Halfway.")], targetKm: 8)
        #expect(e.evaluate(state: state(elapsed: 600, km: 3.9, phase: .walk), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 620, km: 4.1, phase: .walk), events: [])?.message == "Halfway.")
    }

    @Test func finalKilometreFiresInsideTheLastKilometre() {
        var e = engine([CueRule(trigger: .finalKilometre, message: "Last one.")], targetKm: 8)
        #expect(e.evaluate(state: state(elapsed: 600, km: 6.5, phase: .walk), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 700, km: 7.2, phase: .walk), events: [])?.message == "Last one.")
    }

    @Test func phaseStartedFiresOnThePhaseChangeEvent() {
        var e = engine([CueRule(trigger: .phaseStarted(.walk), message: "Walk break.", repeats: true)])
        let cue = e.evaluate(state: state(elapsed: 300, phase: .walk), events: [.phaseChanged(.walk)])
        #expect(cue?.message == "Walk break.")
    }

    // MARK: Rate limiting — spec section 4

    @Test func aFlappingHeartRateProducesOneCueNotTwelve() {
        // The single most important test here. Without the 45s urgent floor a
        // heart rate hovering at the boundary would fire on every sample.
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 0),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        var fired = 0
        for second in stride(from: 0.0, through: 40.0, by: 1.0) {
            if e.evaluate(state: state(elapsed: second, hr: 175), events: []) != nil { fired += 1 }
        }
        #expect(fired == 1)
    }

    @Test func urgentCuesRespectTheFortyFiveSecondFloor() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 0),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        #expect(e.evaluate(state: state(elapsed: 0, hr: 175), events: []) != nil)
        #expect(e.evaluate(state: state(elapsed: 44, hr: 175), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 46, hr: 175), events: []) != nil)
    }

    @Test func nonUrgentCuesWaitForAWalkBreak() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true)])
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        // Running: queued, not delivered.
        #expect(e.evaluate(state: state(elapsed: 300, km: 1, phase: .run), events: [.splitCompleted(split)]) == nil)
        #expect(e.pendingCount == 1)
        // Walk break: delivered.
        #expect(e.deliverQueued(at: 320)?.message == "Split.")
    }

    @Test func atMostOneCuePerWalkBreak() {
        var e = engine([
            CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true),
            CueRule(trigger: .halfway, message: "Halfway.")
        ], targetKm: 2)
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 300, km: 1.1, phase: .run), events: [.splitCompleted(split)])
        #expect(e.pendingCount == 2)
        #expect(e.deliverQueued(at: 310) != nil)
        // Second one waits for the *next* break rather than emptying the queue
        // into a single sixty-second window.
        #expect(e.deliverQueued(at: 320) == nil)
        #expect(e.pendingCount == 1)
    }

    @Test func ninetySecondsBetweenAnyTwoCues() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true)])
        let one = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 300, km: 1, phase: .run), events: [.splitCompleted(one)])
        #expect(e.deliverQueued(at: 300) != nil)

        let two = Split(index: 2, distanceMeters: 2000, elapsed: 600, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 380, km: 2, phase: .run), events: [.splitCompleted(two)])
        #expect(e.deliverQueued(at: 380) == nil)   // only 80s since the last
        #expect(e.deliverQueued(at: 395) != nil)   // 95s
    }

    @Test func nonRepeatingRulesFireOnce() {
        var e = engine([CueRule(trigger: .phaseStarted(.walk), message: "Walk.", repeats: false)])
        #expect(e.evaluate(state: state(elapsed: 300, phase: .walk), events: [.phaseChanged(.walk)]) != nil)
        #expect(e.evaluate(state: state(elapsed: 600, phase: .walk), events: [.phaseChanged(.walk)]) == nil)
    }

    @Test func aStaleCueIsDroppedRatherThanDeliveredLate() {
        // "Halfway" arriving at 80% is worse than silence.
        var e = engine([CueRule(trigger: .halfway, message: "Halfway.")], targetKm: 10)
        _ = e.evaluate(state: state(elapsed: 600, km: 5.1, phase: .run), events: [])
        #expect(e.pendingCount == 1)
        #expect(e.deliverQueued(at: 780) == nil)   // 180s later: stale
        #expect(e.pendingCount == 0)
    }

    @Test func zoneCuesAreSuppressedDuringAWalkBreak() {
        // Heart rate is *supposed* to fall during a walk break, so a drift
        // warning there is noise. Spec section 12, question 1.
        var e = engine([CueRule(trigger: .zoneBelow(floor: "Z1", sustainedSec: 0),
                                message: "Pick it up.", urgency: .immediate, repeats: true)])
        #expect(e.evaluate(state: state(elapsed: 300, hr: 120, phase: .walk), events: []) == nil)
    }
}
