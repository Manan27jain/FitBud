import Foundation
import HealthKit

enum HealthAuthorizationError: Error {
    case unavailable
}

/// Requests the HealthKit permissions FitBud needs.
///
/// Read types cover both live workout metrics and the recovery signals the
/// history probe (and, from Stage 4, the coach) depends on.
struct HealthAuthorization {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKObjectType.workoutType()
    ]

    func requestPermissions() async throws {
        guard Self.isAvailable else { throw HealthAuthorizationError.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }
}
