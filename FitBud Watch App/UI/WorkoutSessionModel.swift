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
        engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: configuration.segments),
            runWalk: configuration.runWalk
        )
        do {
            try await recorder.start(configuration)
            phase = .running
            pump()
        } catch {
            errorMessage = "Couldn't start: \(error.localizedDescription)"
        }
    }

    private func pump() {
        // This `Task` inherits `@MainActor` from the enclosing type, so the
        // property accesses below need no `await` and no extra hopping.
        pumpTask = Task { [weak self] in
            guard let self else { return }
            for await metrics in self.recorder.metrics {
                guard var engine = self.engine else { continue }
                let events = engine.ingest(metrics)
                self.apply(engine: engine, events: events)
            }
        }
    }

    private func apply(engine: WorkoutEngine, events: [WorkoutEvent]) {
        self.engine = engine
        state = engine.state
        for event in events {
            if let haptic = haptic(for: event) { haptics.play(haptic) }
        }
    }

    func pause() async {
        try? await recorder.pause()
        phase = .paused
    }

    func resume() async {
        try? await recorder.resume()
        phase = .running
    }

    func end() async {
        pumpTask?.cancel()
        do {
            let workout = try await recorder.end(splits: state.splits)
            phase = .finished(workout)
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
