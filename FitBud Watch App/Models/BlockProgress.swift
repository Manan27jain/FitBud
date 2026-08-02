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

/// The runs that fall inside `week`, matched by calendar day.
///
/// Matching is on the plan's own `yyyy-MM-dd` day strings rather than on `Date`
/// comparison, for the reason `TrainingPlan.dayKey(for:)` documents: a plan day
/// is a calendar day, and comparing `Date`s drags in timezone and DST questions
/// a calendar day does not have.
func runs(in week: PlanWeek, from runs: [HistoricRun]) -> [HistoricRun] {
    let weekDayKeys = Set(week.days.map(\.date))
    return runs.filter { weekDayKeys.contains(TrainingPlan.dayKey(for: $0.date)) }
}

/// The run recorded on `day`, if there is one.
func run(on day: PlanDay, from runs: [HistoricRun]) -> HistoricRun? {
    runs.first { TrainingPlan.dayKey(for: $0.date) == day.date }
}

/// What the athlete actually did in one plan week, against what it asked for.
struct WeekCompletion: Equatable, Sendable {
    let completedKm: Double
    let plannedKm: Double
    let completedSessions: Int
    let plannedSessions: Int

    /// Completed volume as a fraction of planned, capped at 1 so an overshoot
    /// does not draw a bar past its own track.
    var volumeFraction: Double {
        guard plannedKm > 0 else { return 0 }
        return min(completedKm / plannedKm, 1)
    }
}

/// Completion for any week of the block — the plan browser asks this of all
/// nine, where `blockProgress` below asks it of the current one only.
func weekCompletion(week: PlanWeek, runs allRuns: [HistoricRun]) -> WeekCompletion {
    let matched = runs(in: week, from: allRuns)
    return WeekCompletion(
        completedKm: matched.reduce(0) { $0 + $1.distanceKm },
        plannedKm: week.targetKm,
        completedSessions: matched.count,
        plannedSessions: week.days.filter(\.isRunningSession).count
    )
}

/// The athlete's position in the block as of `asOf`, or `nil` if that date falls
/// outside the plan entirely.
///
/// Volume and session counts are for the *current week only* — the home screen's
/// question is "how am I doing this week", not "how am I doing overall", because
/// the week is the unit the plan progresses in.
func blockProgress(plan: TrainingPlan, runs allRuns: [HistoricRun], asOf date: Date) -> BlockProgress? {
    guard let week = plan.week(containing: date) else { return nil }

    let runsThisWeek = runs(in: week, from: allRuns)
    let completion = weekCompletion(week: week, runs: allRuns)

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
        plannedKm: completion.plannedKm,
        completedKm: completion.completedKm,
        plannedSessions: completion.plannedSessions,
        completedSessions: completion.completedSessions,
        easyShare: easyShare
    )
}
