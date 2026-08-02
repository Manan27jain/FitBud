import Foundation

enum PlanStoreError: LocalizedError {
    case notBundled(String)
    case undecodable(Error)

    var errorDescription: String? {
        switch self {
        case let .notBundled(name):
            "The training plan '\(name).json' isn't in the app bundle."
        case let .undecodable(error):
            "The training plan couldn't be read: \(error.localizedDescription)"
        }
    }
}

/// Loads the training plan.
///
/// `loadBundled` returns the plan exactly as it ships. `effectivePlan` returns
/// the plan as the athlete should see it — today those are the same thing, and
/// every view goes through `effectivePlan` so that when accepted adaptations
/// arrive they apply in one place rather than at every call site.
enum PlanStore {
    static let bundledPlanName = "half-2026-09-27"

    static func loadBundled(name: String = bundledPlanName) throws -> TrainingPlan {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw PlanStoreError.notBundled(name)
        }
        do {
            return try JSONDecoder().decode(TrainingPlan.self, from: Data(contentsOf: url))
        } catch {
            throw PlanStoreError.undecodable(error)
        }
    }

    /// The plan with any accepted adaptations applied. Identical to
    /// `loadBundled` until Plan B introduces the overlay.
    static func effectivePlan(name: String = bundledPlanName) throws -> TrainingPlan {
        try loadBundled(name: name)
    }
}
