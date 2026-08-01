import Foundation
import Observation

/// Bridges the pure engine to SwiftUI: owns the recorder, pumps its metric
/// stream through the engine, and plays haptics for the events that come out.
@MainActor
@Observable
final class WorkoutSessionModel {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished(CompletedWorkout)
    }

    private(set) var phase: Phase = .idle
    private(set) var state = WorkoutState()
    private(set) var errorMessage: String?
    /// Zone time from the finished workout. `state` is cleared by `reset()`, but
    /// the summary still needs this after the run has ended.
    private(set) var finishedTimeInZone: [String: TimeInterval] = [:]

    private var recorder: WorkoutRecording
    /// The recorder this model was configured with — the real one in
    /// production, a test double under test. `startDemo()` swaps `recorder`
    /// for a scripted one that never touches HealthKit; `reset()` restores it
    /// from here so a debug session's demo run can't silently leave every
    /// later *real* session on the fake recorder for the rest of the launch.
    /// A no-op wherever `recorder` was never swapped away from this.
    private let configuredRecorder: WorkoutRecording
    private let haptics: HapticPlaying
    private var engine: WorkoutEngine?
    private var pumpTask: Task<Void, Never>?
    private var isEnding = false

    // `recorder` can't default directly to `HealthKitWorkoutRecorder()`: default
    // argument expressions are type-checked outside the initializer's own
    // main-actor isolation, so a default value calling a `@MainActor`-isolated
    // initializer doesn't compile even though every caller of this `init` is
    // already on the main actor. Defaulting to `nil` and constructing inside
    // the (actor-isolated) init body sidesteps that without changing behavior.
    init(recorder: WorkoutRecording? = nil, haptics: HapticPlaying = WatchHaptics()) {
        let recorder = recorder ?? HealthKitWorkoutRecorder()
        self.recorder = recorder
        self.configuredRecorder = recorder
        self.haptics = haptics
    }

    func start(_ configuration: WorkoutConfiguration) async {
        // A previous attempt's error text and metrics must not bleed into this
        // workout: otherwise a failed start leaves "Couldn't start: …" on screen
        // for the whole of the successful run that follows it.
        pumpTask?.cancel()
        pumpTask = nil
        errorMessage = nil
        state = WorkoutState()
        engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: configuration.segments),
            runWalk: configuration.runWalk
        )
        do {
            // The stream belongs to this workout, so a failed start can never
            // hand a finished stream to the next one.
            let metrics = try await recorder.start(configuration)
            phase = .running
            pump(metrics)
        } catch {
            engine = nil
            errorMessage = "Couldn't start: \(error.localizedDescription)"
        }
    }

#if DEBUG
    /// Starts a scripted workout against `DemoWorkoutRecorder` so the UI can be
    /// seen on a simulator, which has no heart-rate sensor. Debug builds only.
    func startDemo() async {
        recorder = DemoWorkoutRecorder()
        await start(.longRun5to1)
    }
#endif

    private func pump(_ metrics: AsyncThrowingStream<LiveMetrics, Error>) {
        // This `Task` inherits `@MainActor` from the enclosing type, so the
        // property accesses below need no `await` and no extra hopping.
        pumpTask = Task { [weak self] in
            do {
                for try await sample in metrics {
                    guard let self else { return }
                    guard var engine = self.engine else { continue }
                    let events = engine.ingest(sample)
                    self.apply(engine: engine, events: events)
                }
            } catch {
                // The stream only throws when the recorder's underlying
                // session fails on its own (see `HealthKitWorkoutRecorder`'s
                // `didFailWithError`); a normal `end()` finishes it without
                // an error. That makes this catch block the model's only
                // signal that the session died mid-workout, so route to the
                // same recoverable summary a failed `end()` produces instead
                // of leaving the live screen frozen on its last values.
                guard let self else { return }
                self.errorMessage = "Workout session failed: \(error.localizedDescription)"
                self.finish(self.unsavedWorkout())
            }
        }
    }

    private func apply(engine: WorkoutEngine, events: [WorkoutEvent]) {
        self.engine = engine
        state = engine.state
        for event in events {
            haptics.play(haptic(for: event))
        }
    }

    func pause() async {
        do {
            try await recorder.pause()
            phase = .paused
        } catch {
            errorMessage = "Couldn't pause: \(error.localizedDescription)"
        }
    }

    func resume() async {
        do {
            try await recorder.resume()
            phase = .running
        } catch {
            errorMessage = "Couldn't resume: \(error.localizedDescription)"
        }
    }

    func end() async {
        // `end()` suspends for as long as HealthKit takes to save, and the End
        // button stays tappable throughout. A second tap — trivially easy with
        // cold hands — used to re-enter here, call `session.end()` on a session
        // the first call had already ended, and replace a perfectly good saved
        // summary with "Couldn't save to Health". Observed on the simulator.
        guard !isEnding else { return }
        isEnding = true
        defer { isEnding = false }

        // `recorder.end(splits:)` needs the splits array as an argument, and
        // it only finishes the `metrics` stream (via `continuation.finish()`)
        // *inside* that call — after the splits have already been handed
        // over. So we can't call it first and read a post-drain `state.splits`
        // afterwards; that would be circular. Instead we give `pump()`'s
        // `for await` loop a chance to run before we snapshot splits: if
        // HealthKit already delivered a final `LiveMetrics` sample that would
        // complete the last kilometre split, it is sitting in the stream's
        // buffer, and `AsyncStream` resumes a suspended `for await` as soon as
        // a value is available — without an extra suspension per element — so
        // one `Task.yield()` is enough to let the pump loop drain the current
        // backlog and update `state.splits` before we cancel it. Cancelling
        // first (the previous behavior) risked dropping that sample entirely.
        await Task.yield()
        pumpTask?.cancel()
        pumpTask = nil

        let splits = state.splits
        do {
            let workout = try await recorder.end(splits: splits)
            // A stale message from an earlier pause/resume failure (or a
            // session failure the pump loop already recorded) must not
            // render under a summary that in fact saved successfully —
            // `SummaryView` treats any non-nil `errorMessage` as "this run
            // wasn't saved".
            errorMessage = nil
            finish(workout)
        } catch {
            // Losing the HealthKit save is bad; being trapped on a frozen live
            // screen after a two-hour run is worse. The recorder has already
            // torn its session down, so retrying cannot succeed — go to the
            // summary anyway, built from the state we accumulated live, and say
            // plainly that it wasn't saved. The athlete can read their run and
            // leave.
            errorMessage = "Couldn't save to Health: \(error.localizedDescription)"
            finish(unsavedWorkout())
        }
    }

    /// The one door into `.finished`, used by a successful `end()`, a failed
    /// `end()`, and `pump()`'s catch block (the session dying on its own).
    /// Three call sites used to each assign `finishedTimeInZone` themselves;
    /// one of them — the session-failure path — didn't, so an athlete whose
    /// watch dropped the session mid-run got a summary with an empty zone
    /// breakdown despite `state.timeInZone` being full of real data. Funneling
    /// every route through here means there is exactly one place responsible
    /// for capturing it, not three to keep in sync.
    private func finish(_ workout: CompletedWorkout) {
        finishedTimeInZone = state.timeInZone
        phase = .finished(workout)
    }

    /// Reconstructs a summary from live state when HealthKit refuses to hand one
    /// back. `state.elapsed` excludes paused time, matching a real
    /// `CompletedWorkout.duration`; the heart rate is the last sample seen
    /// rather than a true average, which is the best available here.
    private func unsavedWorkout() -> CompletedWorkout {
        let end = Date()
        return CompletedWorkout(
            start: end.addingTimeInterval(-state.elapsed),
            end: end,
            duration: state.elapsed,
            distanceMeters: state.distanceMeters,
            activeEnergyKcal: state.activeEnergyKcal,
            averageHeartRate: state.heartRate,
            splits: state.splits
        )
    }

    /// Returns to the start screen so a second workout can be recorded without
    /// force-quitting the app.
    func reset() {
        pumpTask?.cancel()
        pumpTask = nil
        engine = nil
        state = WorkoutState()
        errorMessage = nil
        finishedTimeInZone = [:]
        phase = .idle
        recorder = configuredRecorder
    }
}
