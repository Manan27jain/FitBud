import Foundation

/// The coaching that plays when the model is unreachable.
///
/// Deliberately plain. Generic encouragement pretending to be personal is worse
/// than encouragement that is honestly generic — and this only ever plays when
/// the personal version could not be fetched.
func defaultBrief(targetZone: String, sessionTitle: String) -> SessionBrief {
    let opening = "\(sessionTitle). Keep it in \(targetZone) and let the walk breaks work."
    let rules = [
        CueRule(
            trigger: .zoneAbove(ceiling: targetZone, sustainedSec: 30),
            message: "Above easy. Ease off and let it come down.",
            urgency: .immediate,
            repeats: true
        ),
        CueRule(
            trigger: .zoneBelow(floor: "Z1", sustainedSec: 60),
            message: "You can pick it up a little.",
            repeats: true
        ),
        CueRule(trigger: .phaseStarted(.walk), message: "Walk break. Breathe.", repeats: true),
        CueRule(trigger: .splitCompleted(index: nil), message: "Another kilometre down.", repeats: true),
        CueRule(trigger: .halfway, message: "Halfway. Still feeling easy?"),
        CueRule(trigger: .finalKilometre, message: "Last kilometre. Finish strong.")
    ]
    return SessionBrief(opening: opening, rules: rules)
}

/// Convenience for a plan day, defaulting the ceiling to Z2 when the day names
/// no zone — the plan's own default for easy running.
func defaultBrief(for day: PlanDay?) -> SessionBrief {
    defaultBrief(targetZone: day?.zone ?? "Z2", sessionTitle: day?.title ?? "Run")
}
