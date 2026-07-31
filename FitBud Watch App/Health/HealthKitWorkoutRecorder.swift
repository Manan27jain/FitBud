import Foundation
import HealthKit

/// Records an outdoor run using `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
///
/// The session is what keeps the app alive and collecting while the wrist is
/// down, so it must be started even for an unstructured run.
@MainActor
final class HealthKitWorkoutRecorder: NSObject, WorkoutRecording {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var continuation: AsyncStream<LiveMetrics>.Continuation?

    private var latestDistance: Double = 0
    private var latestEnergy: Double = 0
    private var latestHeartRate: Double?
    private var heartRateSum: Double = 0
    private var heartRateCount: Int = 0

    let metrics: AsyncStream<LiveMetrics>

    override init() {
        var capturedContinuation: AsyncStream<LiveMetrics>.Continuation!
        metrics = AsyncStream { capturedContinuation = $0 }
        super.init()
        continuation = capturedContinuation
    }

    func start(_ configuration: WorkoutConfiguration) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutRecordingError.healthDataUnavailable
        }

        let hkConfiguration = HKWorkoutConfiguration()
        hkConfiguration.activityType = .running
        hkConfiguration.locationType = .outdoor

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
            emit()
        } catch {
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

        let end = Date()
        session.end()
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
        continuation?.finish()

        self.session = nil
        self.builder = nil

        return CompletedWorkout(
            start: startDate,
            end: end,
            distanceMeters: latestDistance,
            activeEnergyKcal: latestEnergy,
            averageHeartRate: heartRateCount > 0 ? heartRateSum / Double(heartRateCount) : nil,
            splits: splits
        )
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
}

extension HealthKitWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.continuation?.finish() }
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
                        self.heartRateSum += value
                        self.heartRateCount += 1
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
