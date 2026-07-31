import Foundation
import HealthKit

/// Answers spec §12.1: how deep is the watch's local HealthKit store?
///
/// For each metric the coach depends on, finds the oldest available sample and
/// counts how many exist. Run once on a real device — the simulator has no
/// health data and will report every metric as empty.
struct HealthHistoryProbe {
    struct ProbeResult: Identifiable, Equatable {
        var id: String { metric }
        let metric: String
        let oldestSample: Date?
        let newestSample: Date?
        let sampleCount: Int
        /// Non-nil when the query itself failed — almost always denied read
        /// access. Without this, "the watch keeps no history" and "we were never
        /// allowed to look" are indistinguishable, and this probe exists
        /// precisely to choose Stage 4's baseline strategy between them.
        let failure: String?

        init(
            metric: String,
            oldestSample: Date?,
            newestSample: Date?,
            sampleCount: Int,
            failure: String? = nil
        ) {
            self.metric = metric
            self.oldestSample = oldestSample
            self.newestSample = newestSample
            self.sampleCount = sampleCount
            self.failure = failure
        }

        var spanDays: Int? {
            guard let oldestSample, let newestSample else { return nil }
            return Calendar.current.dateComponents([.day], from: oldestSample, to: newestSample).day
        }
    }

    private let store = HKHealthStore()

    private var probedTypes: [(String, HKSampleType)] {
        [
            ("Resting HR", HKQuantityType(.restingHeartRate)),
            ("HRV (SDNN)", HKQuantityType(.heartRateVariabilitySDNN)),
            ("VO2 max", HKQuantityType(.vo2Max)),
            ("Sleep", HKCategoryType(.sleepAnalysis)),
            ("Workouts", HKObjectType.workoutType())
        ]
    }

    func probe() async -> [ProbeResult] {
        var results: [ProbeResult] = []
        for (name, type) in probedTypes {
            results.append(await probe(name: name, type: type))
        }
        return results
    }

    private func probe(name: String, type: HKSampleType) async -> ProbeResult {
        let (samples, error) = await fetchAll(type: type)
        let dates = samples.map(\.startDate).sorted()
        return ProbeResult(
            metric: name,
            oldestSample: dates.first,
            newestSample: dates.last,
            sampleCount: samples.count,
            failure: error?.localizedDescription
        )
    }

    private func fetchAll(type: HKSampleType) async -> (samples: [HKSample], error: Error?) {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                continuation.resume(returning: (samples ?? [], error))
            }
            store.execute(query)
        }
    }
}
