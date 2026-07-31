import Foundation
import Testing
@testable import FitBud_Watch_App

/// A `WorkoutRecording` whose failures and metric samples the test drives
/// directly. Deliberately minimal: it exists because the recorder is the only
/// seam through which the model's lifecycle bugs are reachable, and none of them
/// are reproducible against real HealthKit in a test bundle.
@MainActor
final class FakeWorkoutRecorder: WorkoutRecording {
    var startError: Error?
    var endError: Error?
    var pauseError: Error?
    /// Holds `end()` suspended, so a test can tap End again mid-save.
    var endDelay: Duration?
    private(set) var startCount = 0
    private(set) var endCount = 0
    /// Set once `end()` has torn the session down, mirroring the real recorder:
    /// a second `end()` can never succeed.
    private(set) var isRunning = false

    private var continuation: AsyncThrowingStream<LiveMetrics, Error>.Continuation?

    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncThrowingStream<LiveMetrics, Error> {
        startCount += 1
        continuation?.finish()
        continuation = nil
        if let startError {
            isRunning = false
            throw startError
        }
        var captured: AsyncThrowingStream<LiveMetrics, Error>.Continuation!
        let stream = AsyncThrowingStream<LiveMetrics, Error> { captured = $0 }
        continuation = captured
        isRunning = true
        return stream
    }

    func pause() async throws {
        if let pauseError { throw pauseError }
    }
    func resume() async throws {}

    func end(splits: [Split]) async throws -> CompletedWorkout {
        endCount += 1
        if let endDelay { try? await Task.sleep(for: endDelay) }
        continuation?.finish()
        continuation = nil
        isRunning = false
        if let endError { throw endError }
        return CompletedWorkout(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1_800),
            duration: 1_800,
            distanceMeters: 5_000,
            activeEnergyKcal: 320,
            averageHeartRate: 148,
            splits: splits
        )
    }

    /// Pushes one sample into the current workout's stream.
    func emit(_ metrics: LiveMetrics) {
        continuation?.yield(metrics)
    }

    /// Mimics `HKWorkoutSession`'s `didFailWithError`: finishes the stream by
    /// throwing rather than a plain `finish()`, the distinction
    /// `WorkoutSessionModel.pump(_:)` relies on to notice a session died on
    /// its own.
    func failSession(_ error: Error) {
        continuation?.finish(throwing: error)
        continuation = nil
    }
}

final class RecordingHaptics: HapticPlaying {
    private(set) var played: [WorkoutHaptic] = []

    func play(_ haptic: WorkoutHaptic) {
        played.append(haptic)
    }
}

@MainActor
struct WorkoutSessionModelTests {
    private func makeModel() -> (WorkoutSessionModel, FakeWorkoutRecorder, RecordingHaptics) {
        let recorder = FakeWorkoutRecorder()
        let haptics = RecordingHaptics()
        return (WorkoutSessionModel(recorder: recorder, haptics: haptics), recorder, haptics)
    }

    /// The pump loop runs in its own main-actor `Task`, so a yield alone is not a
    /// guarantee. Poll briefly instead of sleeping a fixed amount.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Regression test for the metric stream dying with the first failed start.
    /// The stream used to be created once per recorder, so the failure path's
    /// `finish()` poisoned every later workout: HealthKit recorded, the screen
    /// showed 0:00 / 0.00 km for the whole run, and the summary said 0 m.
    @Test func aFailedStartDoesNotBreakTheNextWorkout() async {
        let (model, recorder, _) = makeModel()

        recorder.startError = WorkoutRecordingError.workoutSavingNotAuthorized
        await model.start(.longRun4to1)
        #expect(model.phase == .idle)
        #expect(model.errorMessage != nil)

        recorder.startError = nil
        await model.start(.longRun4to1)
        #expect(model.phase == .running)
        #expect(recorder.startCount == 2)

        recorder.emit(LiveMetrics(elapsed: 61, distanceMeters: 200, heartRate: 143, activeEnergyKcal: 18))
        await waitUntil { model.state.elapsed == 61 }
        #expect(model.state.elapsed == 61)
        #expect(model.state.distanceMeters == 200)
        #expect(model.state.heartRate == 143)
    }

    @Test func aFailedEndStillLeavesTheAthleteASummaryTheyCanLeaveFrom() async {
        let (model, recorder, _) = makeModel()
        await model.start(.longRun4to1)
        recorder.emit(LiveMetrics(elapsed: 7_200, distanceMeters: 12_000, heartRate: 151, activeEnergyKcal: 900))
        await waitUntil { model.state.distanceMeters == 12_000 }

        recorder.endError = WorkoutRecordingError.sessionFailed(URLError(.timedOut))
        await model.end()

        // Not stuck on a frozen live screen after a two-hour run.
        #expect(model.phase != .running)
        #expect(model.phase != .paused)
        #expect(model.errorMessage != nil)

        guard case let .finished(workout) = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }
        // The run the athlete actually did is still readable, even unsaved.
        #expect(workout.distanceMeters == 12_000)
        #expect(workout.duration == 7_200)

        // And the way out still works.
        model.reset()
        #expect(model.phase == .idle)
        #expect(model.errorMessage == nil)
    }

    @Test func startClearsStaleStateAndErrorText() async {
        let (model, recorder, _) = makeModel()

        recorder.startError = WorkoutRecordingError.healthDataUnavailable
        await model.start(.openEasyRun)
        #expect(model.errorMessage != nil)

        recorder.startError = nil
        await model.start(.openEasyRun)
        // The red "Couldn't start: …" text used to persist for the whole run.
        #expect(model.errorMessage == nil)
        #expect(model.state.elapsed == 0)
        #expect(model.state.distanceMeters == 0)
        #expect(model.state.splits.isEmpty)
    }

    @Test func staleMetricsDoNotSurviveIntoASecondWorkout() async {
        let (model, recorder, _) = makeModel()
        await model.start(.openEasyRun)
        recorder.emit(LiveMetrics(elapsed: 900, distanceMeters: 3_000, heartRate: 150))
        await waitUntil { model.state.distanceMeters == 3_000 }
        await model.end()

        await model.start(.openEasyRun)
        #expect(model.state.distanceMeters == 0)
        #expect(model.state.elapsed == 0)
    }

    /// Important 4 composed with Critical 1: leaving the summary must genuinely
    /// return the app to a state where a second run records.
    @Test func returningFromTheSummaryAllowsASecondWorkout() async {
        let (model, recorder, _) = makeModel()

        await model.start(.longRun4to1)
        recorder.emit(LiveMetrics(elapsed: 300, distanceMeters: 900, heartRate: 140))
        await waitUntil { model.state.distanceMeters == 900 }
        await model.end()
        guard case .finished = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }

        model.reset()
        #expect(model.phase == .idle)

        await model.start(.longRun4to1)
        #expect(model.phase == .running)
        recorder.emit(LiveMetrics(elapsed: 42, distanceMeters: 120, heartRate: 138))
        await waitUntil { model.state.distanceMeters == 120 }
        #expect(model.state.elapsed == 42)
        #expect(recorder.startCount == 2)
    }

    @Test func splitsRecordedLiveReachTheSavedWorkout() async {
        let (model, recorder, _) = makeModel()
        await model.start(.openEasyRun)
        recorder.emit(LiveMetrics(elapsed: 540, distanceMeters: 1_000, heartRate: 155))
        await waitUntil { model.state.splits.count == 1 }

        await model.end()
        guard case let .finished(workout) = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }
        #expect(workout.splits.count == 1)
        #expect(workout.splits[0].heartRateAtSplit == 155)
    }

    /// Observed on the simulator: the End button stays live while HealthKit
    /// saves, and a second tap used to report "Couldn't save to Health" over a
    /// run that had in fact been saved.
    @Test func asecondEndTapCannotReplaceASavedSummaryWithAnError() async {
        let (model, recorder, _) = makeModel()
        await model.start(.openEasyRun)
        recorder.emit(LiveMetrics(elapsed: 600, distanceMeters: 2_000, heartRate: 150))
        await waitUntil { model.state.distanceMeters == 2_000 }

        recorder.endDelay = .milliseconds(200)
        async let firstTap: Void = model.end()
        await waitUntil { recorder.endCount == 1 }
        await model.end()
        await firstTap

        #expect(recorder.endCount == 1)
        #expect(model.errorMessage == nil)
        guard case let .finished(workout) = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }
        // The recorder's saved totals, not the locally rebuilt fallback.
        #expect(workout.distanceMeters == 5_000)
    }

    @Test func eventsFromTheEngineReachTheHaptics() async {
        let (model, recorder, haptics) = makeModel()
        await model.start(.longRun4to1)
        recorder.emit(LiveMetrics(elapsed: 1, distanceMeters: 0))
        recorder.emit(LiveMetrics(elapsed: 241, distanceMeters: 700))
        await waitUntil { haptics.played.contains(.startWalking) }
        #expect(haptics.played.contains(.startWalking))
    }

    /// A stale message from an earlier failure (here, a failed `pause()`)
    /// must not survive a *successful* `end()` — `SummaryView` treats any
    /// non-nil `errorMessage` as "this run wasn't saved", and this run was.
    @Test func endClearsAStaleErrorMessageOnSuccess() async {
        let (model, recorder, _) = makeModel()
        await model.start(.openEasyRun)

        recorder.pauseError = WorkoutRecordingError.notRunning
        await model.pause()
        #expect(model.errorMessage != nil)

        recorder.pauseError = nil
        await model.end()

        #expect(model.errorMessage == nil)
        guard case .finished = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }
    }

    /// Regression test for the session dying on its own (`didFailWithError`
    /// in the real recorder) while the model stayed `.running`. The metric
    /// stream used to just go quiet, freezing the live screen on its last
    /// values with no indication anything had gone wrong. `failSession(_:)`
    /// finishes the fake's stream by throwing, mirroring the real delegate,
    /// which `pump(_:)` must route to the same recoverable summary a failed
    /// `end()` produces.
    @Test func aSessionFailureRoutesToARecoverableSummaryInsteadOfFreezing() async {
        let (model, recorder, _) = makeModel()
        await model.start(.openEasyRun)
        recorder.emit(LiveMetrics(elapsed: 300, distanceMeters: 900, heartRate: 140))
        await waitUntil { model.state.distanceMeters == 900 }

        recorder.failSession(WorkoutRecordingError.sessionFailed(URLError(.networkConnectionLost)))
        await waitUntil {
            if case .finished = model.phase { return true }
            return false
        }

        #expect(model.errorMessage != nil)
        guard case let .finished(workout) = model.phase else {
            Issue.record("expected a summary, got \(model.phase)")
            return
        }
        // Never handed to `recorder.end(splits:)` — reconstructed from the
        // live state accumulated before the session failed.
        #expect(workout.distanceMeters == 900)
        #expect(workout.duration == 300)
        #expect(recorder.endCount == 0)
    }
}
