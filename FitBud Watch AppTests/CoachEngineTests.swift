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

    @Test func theMinimumGapSubsumesOnePerWalkBreak() throws {
        // Rule 4 ("at most one cue per walk break") isn't enforced by any
        // break-identity bookkeeping in the engine — it holds only because
        // minimumGap outlasts every walk break the plan actually contains.
        // This reads the real bundled plan rather than hardcoding 60s, so it
        // breaks loudly if a future plan ever carries a walk break that
        // catches up to minimumGap.
        let plan = try PlanStore.loadBundled()
        let walkBreakMinutes = plan.weeks.flatMap(\.days).compactMap { $0.runWalk?.walkMin }
        let longestWalkBreakSec = (walkBreakMinutes.max() ?? 0) * 60
        #expect(CoachEngine.minimumGap > longestWalkBreakSec)
    }
}

@MainActor
struct CoachWiringTests {
    /// Returns a brief immediately; records what it was asked for.
    final class FakeProvider: AIProviding, @unchecked Sendable {
        let id: ProviderID = .openAI
        var briefToReturn: SessionBrief?
        var briefError: (any Error)?
        /// Mimics a real network round trip, the way `FakeWorkoutRecorder`'s
        /// `startDelay` mimics `beginCollection`'s.
        var briefDelay: Duration?
        private(set) var briefCallCount = 0

        func brief(context: CoachContext) async throws -> SessionBrief {
            briefCallCount += 1
            if let briefDelay { try? await Task.sleep(for: briefDelay) }
            if let briefError { throw briefError }
            return briefToReturn ?? SessionBrief(opening: "Go", rules: [])
        }
        func liveCue(context: LiveCoachContext) async throws -> String { "Keep going." }
        func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
            WorkoutAnalysis(summary: "Good run.", takeaway: "Keep it easy.")
        }
    }

    final class RecordingSpeaker: CoachSpeaking, @unchecked Sendable {
        var canBeHeard = true
        private(set) var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
        func stop() {}
    }

    @Test func aFailedBriefStillLeavesTheCoachWorking() async {
        // The run must never be blocked or left silent by an AI failure.
        let provider = FakeProvider()
        provider.briefError = AIProvidingError.badResponse(500)
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: provider, speaker: RecordingSpeaker(), settings: CoachSettings())

        await model.start(.openEasyRun)
        // The default bundle is in place, so cues can still fire.
        #expect(model.coachIsReady)
    }

    @Test func aCueIsSpokenOnlyWhenSpeechIsEnabled() {
        let speaker = RecordingSpeaker()
        let settings = CoachSettings()
        settings.isSpeechEnabled = false
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: speaker, settings: settings)

        model.present(Cue(id: UUID(), message: "Ease off.", urgency: .immediate, firedAt: 100))
        #expect(model.currentCue?.message == "Ease off.")
        #expect(speaker.spoken.isEmpty)

        settings.isSpeechEnabled = true
        model.present(Cue(id: UUID(), message: "Walk break.", urgency: .atNextBreak, firedAt: 200))
        #expect(speaker.spoken == ["Walk break."])
    }

    @Test func dismissingClearsTheMessage() {
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: RecordingSpeaker(), settings: CoachSettings())
        model.present(Cue(id: UUID(), message: "Halfway.", urgency: .atNextBreak, firedAt: 100))
        #expect(model.currentCue != nil)
        model.dismissCue()
        #expect(model.currentCue == nil)
    }

    @Test func resetClearsCoachState() {
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: RecordingSpeaker(), settings: CoachSettings())
        model.present(Cue(id: UUID(), message: "Halfway.", urgency: .atNextBreak, firedAt: 100))
        model.reset()
        #expect(model.currentCue == nil)
        #expect(model.coachIsReady == false)
    }

    /// Regression test: a slow brief used to install itself and speak its
    /// opening into whatever workout happened to be running when it finally
    /// landed, because the only guard was `phase == .running`, and a second
    /// workout satisfies that just as well as the first one did.
    @Test func aBriefThatArrivesAfterResetDoesNotInstallIntoTheNextWorkout() async {
        let provider = FakeProvider()
        provider.briefDelay = .milliseconds(100)
        provider.briefToReturn = SessionBrief(opening: "Stale opening.", rules: [])
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: provider, speaker: RecordingSpeaker(), settings: CoachSettings())

        await model.start(.openEasyRun)
        model.reset()
        // The second workout has no provider of its own, so the only brief
        // that could possibly land during its lifetime is the first
        // workout's late one — which must be rejected.
        model.configureCoach(provider: nil, speaker: RecordingSpeaker(), settings: CoachSettings())
        await model.start(.openEasyRun)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(model.currentCue == nil)
    }

    /// Regression test: swapping in the real brief resets the engine's rate
    /// limiter, and the opening line was presented directly rather than
    /// through `evaluate`, so it bypassed the limiter entirely. A cue that
    /// fired moments before the brief lands must suppress the opening rather
    /// than doubling up inside the 45s floor.
    @Test func theOpeningLineIsSuppressedWhenACueFiredWithinTheFloor() async {
        let provider = FakeProvider()
        provider.briefDelay = .milliseconds(50)
        provider.briefToReturn = SessionBrief(opening: "Fresh opening.", rules: [])
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: provider, speaker: RecordingSpeaker(), settings: CoachSettings())

        await model.start(.openEasyRun)
        model.present(Cue(id: UUID(), message: "Ease off.", urgency: .immediate, firedAt: 0))

        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.currentCue?.message == "Ease off.")
    }
}

/// A haptic player that does nothing, for tests that are not about haptics.
struct SilentHaptics: HapticPlaying {
    func play(_ haptic: WorkoutHaptic) {}
}
