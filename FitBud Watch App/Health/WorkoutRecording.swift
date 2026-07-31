import Foundation

enum WorkoutRecordingError: LocalizedError {
    case healthDataUnavailable
    /// Share permission for workouts was never granted, so nothing could be
    /// saved at the end. Caught before the run rather than after it.
    case workoutSavingNotAuthorized
    case notRunning
    case sessionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "Health data isn't available on this watch."
        case .workoutSavingNotAuthorized:
            "FitBud can't save workouts. Allow it in Settings › Health › Data Access."
        case .notRunning:
            "No workout is running."
        case let .sessionFailed(error):
            error.localizedDescription
        }
    }
}

/// The seam between the workout engine and HealthKit.
///
/// Everything above this protocol is pure and testable; everything below it
/// talks to `HKWorkoutSession`. Stage 2 onwards depends on this type, never on
/// the HealthKit implementation directly.
///
/// `@MainActor` because `HKWorkoutSession` and its live builder are main-actor
/// bound, and because the UI observes the resulting state directly. Without the
/// annotation the `@MainActor` implementation cannot satisfy the protocol.
@MainActor
protocol WorkoutRecording: AnyObject {
    /// Starts recording and returns the metric stream for *this* workout.
    ///
    /// The stream is deliberately a return value rather than a property: it is
    /// scoped to one workout, so a `start()` that throws cannot leave behind a
    /// finished stream for the next attempt to consume. It yields a snapshot
    /// roughly every second and again whenever HealthKit delivers new sensor
    /// data, and finishes when the workout ends or the session fails.
    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncStream<LiveMetrics>
    func pause() async throws
    func resume() async throws
    func end(splits: [Split]) async throws -> CompletedWorkout
}
