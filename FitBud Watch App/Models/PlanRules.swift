import Foundation

/// The plan's own progression limits, read straight from the JSON.
///
/// This is the machine-readable half of the `rules` block: a validator can act
/// on these numbers directly. The `immutable` array beside them is English
/// prose — decoded so the app can quote a rule back to the athlete when a
/// change is refused, but enforced in code rather than parsed.
struct ProgressionCaps: Decodable, Equatable, Sendable {
    /// Maximum weekly volume increase, as a fraction: 0.2 is +20%.
    let weeklyKmIncreaseMax: Double
    /// Maximum long-run increase per step, in kilometres.
    let longRunIncreaseMaxKm: Double
}

/// The `rules` block of the training plan.
///
/// `sleepGate` and `recoveryGate` are present in the JSON and deliberately not
/// decoded: they govern whether *today's* session should be downgraded, which
/// is a separate feature from browsing or reshaping the block. Swift's
/// synthesised decoder ignores keys with no matching property, so they stay
/// available in the file for whenever that feature is built.
struct PlanRules: Decodable, Equatable, Sendable {
    let progressionCaps: ProgressionCaps
    /// Prose, displayed and never parsed. See the type comment above.
    let immutable: [String]
    let zoneDiscipline: String
}
