import Foundation
import HealthKit

/// Reads finished runs back out of HealthKit.
///
/// Deliberately separate from `WorkoutRecording`: this is read-only and must not
/// share a type with the recorder, which is the most safety-critical file in the
/// project and is not to be modified.
@MainActor
protocol WorkoutHistoryReading {
    func recentRuns(since date: Date) async throws -> [HistoricRun]
}

@MainActor
struct HealthKitWorkoutHistory: WorkoutHistoryReading {
    private let store = HKHealthStore()

    func recentRuns(since date: Date) async throws -> [HistoricRun] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, datePredicate])

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        return workouts.map { workout in
            let distanceType = HKQuantityType(.distanceWalkingRunning)
            let heartRateType = HKQuantityType(.heartRate)
            let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
            return HistoricRun(
                id: workout.uuid,
                date: workout.startDate,
                distanceMeters: workout.statistics(for: distanceType)?
                    .sumQuantity()?.doubleValue(for: .meter()) ?? 0,
                duration: workout.duration,
                averageHeartRate: workout.statistics(for: heartRateType)?
                    .averageQuantity()?.doubleValue(for: beatsPerMinute)
            )
        }
    }
}
