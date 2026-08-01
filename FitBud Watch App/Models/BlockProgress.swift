import Foundation

/// Where the athlete stands in the training block, for the home screen.
struct BlockProgress: Equatable, Sendable {
    let daysToRace: Int
    let weekIndex: Int
    let totalWeeks: Int
    let weekFocus: String
    let plannedKm: Double
    let completedKm: Double
    let plannedSessions: Int
    let completedSessions: Int
    /// Fraction of this week's runs whose average heart rate was Z1 or Z2, or
    /// `nil` when there is nothing to judge yet. The plan requires 0.8.
    let easyShare: Double?

    /// Completed volume as a fraction of planned, capped at 1 so an overshoot
    /// does not draw a bar past its own track.
    var volumeFraction: Double {
        guard plannedKm > 0 else { return 0 }
        return min(completedKm / plannedKm, 1)
    }
}

/// The athlete's position in the block as of `asOf`, or `nil` if that date falls
/// outside the plan entirely.
///
/// Volume and session counts are for the *current week only* — the home screen's
/// question is "how am I doing this week", not "how am I doing overall", because
/// the week is the unit the plan progresses in.
func blockProgress(plan: TrainingPlan, runs: [HistoricRun], asOf date: Date) -> BlockProgress? {
    guard let week = plan.week(containing: date) else { return nil }

    let weekDayKeys = Set(week.days.map(\.date))
    let runsThisWeek = runs.filter { weekDayKeys.contains(TrainingPlan.dayKey(for: $0.date)) }

    let runningDays = week.days.filter(\.isRunningSession)
    let easyShare: Double? = runsThisWeek.isEmpty
        ? nil
        : Double(runsThisWeek.filter(\.isEasy).count) / Double(runsThisWeek.count)

    // Week 0 is the two-day calibration bridge, so the block is eight numbered
    // training weeks regardless of how many entries the array holds.
    let totalWeeks = plan.weeks.map(\.index).max() ?? 0

    return BlockProgress(
        daysToRace: plan.daysToRace(from: date),
        weekIndex: week.index,
        totalWeeks: totalWeeks,
        weekFocus: week.focus,
        plannedKm: week.targetKm,
        completedKm: runsThisWeek.reduce(0) { $0 + $1.distanceKm },
        plannedSessions: runningDays.count,
        completedSessions: runsThisWeek.count,
        easyShare: easyShare
    )
}
