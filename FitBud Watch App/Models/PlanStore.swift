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

/// Loads the training plan that ships with the app.
///
/// Stage 4 will rewrite the plan in place after each week; this loader is where
/// that persisted copy will take precedence over the bundled one.
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
}
