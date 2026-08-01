#if DEBUG
import Foundation

/// A fake recorder that plays a scripted workout, for looking at the UI on a
/// simulator that has no heart-rate sensor.
///
/// The heart rate sweeps 130 → 200 bpm and back, so every zone is entered in
/// turn and the ring, scale and zone bar can all be seen doing their job.
/// Compiled out of release builds entirely.
@MainActor
final class DemoWorkoutRecorder: WorkoutRecording {
    private var continuation: AsyncThrowingStream<LiveMetrics, Error>.Continuation?
    private var task: Task<Void, Never>?
    private var elapsed: TimeInterval = 0
    private var distance: Double = 0
    private var isPaused = false

    /// Seconds of simulated workout per real second. The sweep covers all five
    /// zones in about half a minute of watching.
    private let timeScale: Double = 20

    /// The athlete's scripted easy pace, seconds per kilometre (9:00/km).
    private static let basePaceSecPerKm: Double = 540
    /// A scripted mid-sweep fade: pace slows ~25% for a stretch, well after
    /// the first kilometre, then recovers — so `paceFading` has something to
    /// catch on the simulator, where the real sensor stream never fades on
    /// its own. Placed at 925–1010s: inside the third run interval of
    /// `.longRun5to1` (run/walk 300s/60s, so run intervals are 0–300,
    /// 360–660, 720–1020) and in the descending half of the heart-rate
    /// sweep, where HR has dropped back under the Z2 ceiling (~917s). That
    /// keeps it clear of `zoneAbove`, which floods that same immediate-cue
    /// slot for most of the sweep's high stretch and would otherwise starve
    /// this rule of its turn before the window clears at the 1020s walk.
    private static let fadeWindow: Range<TimeInterval> = 925..<1_010
    private static let fadedPaceSecPerKm: Double = basePaceSecPerKm * 1.25

    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncThrowingStream<LiveMetrics, Error> {
        let stream = AsyncThrowingStream<LiveMetrics, Error> { continuation in
            self.continuation = continuation
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.isPaused else { continue }
                self.elapsed += self.timeScale / 2
                self.distance += (self.timeScale / 2) * (1000.0 / Self.paceSecPerKm(at: self.elapsed))
                self.continuation?.yield(
                    LiveMetrics(
                        elapsed: self.elapsed,
                        distanceMeters: self.distance,
                        heartRate: Self.scriptedHeartRate(at: self.elapsed),
                        activeEnergyKcal: self.elapsed * 0.16
                    )
                )
            }
        }
        return stream
    }

    /// Triangle wave from 130 to 200 bpm over a 20-minute period, so the needle
    /// climbs through every zone and comes back down.
    nonisolated static func scriptedHeartRate(at elapsed: TimeInterval) -> Double {
        let period: Double = 1_200
        let position = elapsed.truncatingRemainder(dividingBy: period) / period
        let triangle = position < 0.5 ? position * 2 : (1 - position) * 2
        return 130 + triangle * 70
    }

    /// Roughly 9:00/km, the athlete's target easy pace — except inside
    /// `fadeWindow`, where it slows to demonstrate `paceFading`.
    nonisolated static func paceSecPerKm(at elapsed: TimeInterval) -> Double {
        fadeWindow.contains(elapsed) ? fadedPaceSecPerKm : basePaceSecPerKm
    }

    func pause() async throws { isPaused = true }
    func resume() async throws { isPaused = false }

    func end(splits: [Split]) async throws -> CompletedWorkout {
        task?.cancel()
        continuation?.finish()
        let end = Date()
        return CompletedWorkout(
            start: end.addingTimeInterval(-elapsed),
            end: end,
            duration: elapsed,
            distanceMeters: distance,
            activeEnergyKcal: elapsed * 0.16,
            averageHeartRate: 158,
            splits: splits
        )
    }
}
#endif
