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

    private let recorder: WorkoutRecording
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
        self.recorder = recorder ?? HealthKitWorkoutRecorder()
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

    private func pump(_ metrics: AsyncStream<LiveMetrics>) {
        // This `Task` inherits `@MainActor` from the enclosing type, so the
        // property accesses below need no `await` and no extra hopping.
        pumpTask = Task { [weak self] in
            for await sample in metrics {
                guard let self else { return }
                guard var engine = self.engine else { continue }
                let events = engine.ingest(sample)
                self.apply(engine: engine, events: events)
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
            phase = .finished(workout)
        } catch {
            // Losing the HealthKit save is bad; being trapped on a frozen live
            // screen after a two-hour run is worse. The recorder has already
            // torn its session down, so retrying cannot succeed — go to the
            // summary anyway, built from the state we accumulated live, and say
            // plainly that it wasn't saved. The athlete can read their run and
            // leave.
            errorMessage = "Couldn't save to Health: \(error.localizedDescription)"
            phase = .finished(unsavedWorkout())
        }
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
        phase = .idle
    }
}
