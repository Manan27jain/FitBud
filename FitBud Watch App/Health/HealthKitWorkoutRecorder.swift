import Foundation
import HealthKit

/// Records an outdoor run using `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
///
/// The session is what keeps the app alive and collecting while the wrist is
/// down, so it must be started even for an unstructured run.
@MainActor
final class HealthKitWorkoutRecorder: NSObject, WorkoutRecording {
    /// How often a snapshot is emitted independently of HealthKit deliveries.
    private static let tickInterval: Duration = .seconds(1)

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var continuation: AsyncStream<LiveMetrics>.Continuation?
    private var tickTask: Task<Void, Never>?

    private var latestDistance: Double = 0
    private var latestEnergy: Double = 0
    private var latestHeartRate: Double?
    private var averageHeartRate: Double?

    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncStream<LiveMetrics> {
        // Nothing may survive from a previous attempt: a stream, a ticker or a
        // stale distance total left over from a failed (or completed) workout
        // would corrupt this one.
        teardown()

        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutRecordingError.healthDataUnavailable
        }
        // `requestAuthorization` succeeds even when the athlete denies write
        // access, and `HKLiveWorkoutBuilder` only reports that at
        // `finishWorkout()` — two hours too late. Refuse up front instead.
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw WorkoutRecordingError.workoutSavingNotAuthorized
        }

        let hkConfiguration = HKWorkoutConfiguration()
        hkConfiguration.activityType = .running
        hkConfiguration.locationType = .outdoor

        var capturedContinuation: AsyncStream<LiveMetrics>.Continuation!
        let stream = AsyncStream<LiveMetrics> { capturedContinuation = $0 }
        continuation = capturedContinuation

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: hkConfiguration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: hkConfiguration
            )
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            self.startDate = start
            startTicking()
            emit()
            return stream
        } catch {
            // This stream never reached a consumer, so finishing it costs
            // nothing — and `teardown()` on the next attempt would finish it
            // anyway. Clearing it here keeps the failed object inert.
            teardown()
            throw WorkoutRecordingError.sessionFailed(error)
        }
    }

    func pause() async throws {
        guard let session else { throw WorkoutRecordingError.notRunning }
        session.pause()
    }

    func resume() async throws {
        guard let session else { throw WorkoutRecordingError.notRunning }
        session.resume()
    }

    func end(splits: [Split]) async throws -> CompletedWorkout {
        guard let session, let builder, let startDate else {
            throw WorkoutRecordingError.notRunning
        }

        // Whatever HealthKit does next, this recorder must not be left
        // half-ended: a second `end()` on an already-ended session throws
        // forever, which would trap the athlete on the live screen.
        defer { teardown() }

        // `elapsedTime` is unreadable once collection has ended, so capture it
        // now as the fallback for a workout HealthKit declines to hand back.
        let elapsedBeforeEnding = builder.elapsedTime
        let end = Date()
        session.end()
        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()

        // Prefer the saved workout's own totals. Its `duration` already
        // excludes paused time, which is what `elapsedTime` (and therefore
        // every split) measures — wall-clock `end - start` does not, so after
        // one traffic-light pause the summary would contradict the splits
        // printed directly above it.
        return CompletedWorkout(
            start: workout?.startDate ?? startDate,
            end: workout?.endDate ?? end,
            duration: workout?.duration ?? elapsedBeforeEnding,
            distanceMeters: total(of: .distanceWalkingRunning, in: workout, unit: .meter())
                ?? latestDistance,
            activeEnergyKcal: total(of: .activeEnergyBurned, in: workout, unit: .kilocalorie())
                ?? latestEnergy,
            averageHeartRate: averageHeartRate,
            splits: splits
        )
    }

    private func total(
        of identifier: HKQuantityTypeIdentifier,
        in workout: HKWorkout?,
        unit: HKUnit
    ) -> Double? {
        workout?
            .statistics(for: HKQuantityType(identifier))?
            .sumQuantity()?
            .doubleValue(for: unit)
    }

    /// `HKLiveWorkoutBuilder.elapsedTime` already excludes time spent paused,
    /// which is exactly the contract `LiveMetrics.elapsed` documents. Deriving
    /// elapsed from wall-clock instead would let one traffic-light pause shift
    /// every run/walk transition and segment boundary for the rest of the run.
    private func emit() {
        guard let builder else { return }
        continuation?.yield(
            LiveMetrics(
                elapsed: builder.elapsedTime,
                distanceMeters: latestDistance,
                heartRate: latestHeartRate,
                activeEnergyKcal: latestEnergy
            )
        )
    }

    /// Sample-driven emits alone are not enough: heart rate takes 5-15s to
    /// arrive and GPS lock up to 30s, so the clock would sit at 0:00 for the
    /// opening seconds of every run, and each run/walk or block transition
    /// would be announced only as late as the next sample.
    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard !Task.isCancelled, let self, self.builder != nil else { return }
                self.emit()
            }
        }
    }

    /// Returns the recorder to its pre-workout state. Safe to call repeatedly.
    private func teardown() {
        tickTask?.cancel()
        tickTask = nil
        continuation?.finish()
        continuation = nil
        session = nil
        builder = nil
        startDate = nil
        latestDistance = 0
        latestEnergy = 0
        latestHeartRate = nil
        averageHeartRate = nil
    }
}

extension HealthKitWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Stop ticking and close the stream, but keep `session`/`builder` so
        // `end()` can still run its normal path: it will throw, and the model
        // falls back to a locally-built summary rather than trapping the
        // athlete on a frozen live screen.
        Task { @MainActor in
            self.tickTask?.cancel()
            self.tickTask = nil
            self.continuation?.finish()
        }
    }
}

extension HealthKitWorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType,
                      let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

                switch quantityType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    if let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                        self.latestHeartRate = value
                    }
                    if let average = statistics.averageQuantity()?.doubleValue(for: unit) {
                        self.averageHeartRate = average
                    }
                case HKQuantityType(.distanceWalkingRunning):
                    if let value = statistics.sumQuantity()?.doubleValue(for: .meter()) {
                        self.latestDistance = value
                    }
                case HKQuantityType(.activeEnergyBurned):
                    if let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        self.latestEnergy = value
                    }
                default:
                    continue
                }
            }
            self.emit()
        }
    }
}
