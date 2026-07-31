import Foundation

enum WorkoutRecordingError: Error {
    case healthDataUnavailable
    case notRunning
    case sessionFailed(Error)
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
    /// Emits a snapshot each time HealthKit delivers new sensor data.
    /// Finishes when the workout ends.
    var metrics: AsyncStream<LiveMetrics> { get }

    func start(_ configuration: WorkoutConfiguration) async throws
    func pause() async throws
    func resume() async throws
    func end(splits: [Split]) async throws -> CompletedWorkout
}
