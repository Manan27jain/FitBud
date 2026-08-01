import Foundation
import Observation

/// Loads everything the home screen shows: the plan, recent runs, and the
/// progress derived from both.
@MainActor
@Observable
final class HomeModel {
    private(set) var plan: TrainingPlan?
    private(set) var today: PlanDay?
    private(set) var progress: BlockProgress?
    private(set) var recentRuns: [HistoricRun] = []
    private(set) var loadError: String?
    private(set) var isLoading = true

    private let history: WorkoutHistoryReading

    // `history` can't default directly to `HealthKitWorkoutHistory()`: default
    // argument expressions are type-checked outside the initializer's own
    // main-actor isolation, so a default value calling a `@MainActor`-isolated
    // initializer doesn't compile even though every caller of this `init` is
    // already on the main actor (same issue documented on
    // `WorkoutSessionModel.init`). Defaulting to `nil` and constructing inside
    // the (actor-isolated) init body sidesteps that without changing behavior.
    init(history: WorkoutHistoryReading? = nil) {
        self.history = history ?? HealthKitWorkoutHistory()
    }

    /// Reloads on every appearance: the day rolls over, and a run finished
    /// moments ago should show up without relaunching the app.
    func load(asOf date: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let plan = try PlanStore.loadBundled()
            self.plan = plan
            today = plan.day(on: date)
        } catch {
            loadError = error.localizedDescription
            return
        }

        // Two weeks back covers the current week plus enough context for the
        // recent-runs list without pulling the athlete's whole history.
        let since = Calendar.current.date(byAdding: .day, value: -14, to: date) ?? date
        do {
            recentRuns = try await history.recentRuns(since: since)
        } catch {
            // A history read failure must not take the whole screen down: the
            // plan and today's session are still worth showing.
            recentRuns = []
        }

        if let plan {
            progress = blockProgress(plan: plan, runs: recentRuns, asOf: date)
        }
    }
}
