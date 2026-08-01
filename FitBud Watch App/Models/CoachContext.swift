import Foundation

/// Everything the model is told before a run.
///
/// Rendered to compact text rather than sent as JSON: the model reads prose
/// better than it reads schemas, and this keeps the payload small enough that
/// cost never becomes a design constraint.
struct CoachContext: Equatable, Sendable {
    var sessionTitle: String
    var sessionNotes: String
    var targetKm: Double
    var targetZone: String
    var runWalk: String?

    var daysToRace: Int
    var weekIndex: Int
    var totalWeeks: Int
    var weekFocus: String
    var weekCompletedKm: Double
    var weekPlannedKm: Double
    /// 0…1, or nil when there is nothing to judge yet.
    var easyShare: Double?

    var recentRuns: [String]

    var sleepHours: Double?
    var restingHeartRate: Double?
    var hrv: Double?

    var zoneTable: String

    var promptSummary: String {
        var lines: [String] = []
        lines.append("Today's session: \(sessionTitle), target \(fmt(targetKm))km in \(targetZone).")
        if let runWalk { lines.append("Run/walk: \(runWalk).") }
        if !sessionNotes.isEmpty { lines.append("Plan note: \(sessionNotes)") }
        lines.append("Week \(weekIndex) of \(totalWeeks), \(daysToRace) days to race day. Focus: \(weekFocus)")
        lines.append("This week: \(fmt(weekCompletedKm))km of \(fmt(weekPlannedKm))km planned.")
        if let easyShare {
            lines.append("Easy running this week: \(Int((easyShare * 100).rounded()))% of runs (target 80%).")
        }
        if !recentRuns.isEmpty {
            lines.append("Recent runs:")
            lines.append(contentsOf: recentRuns.map { "  \($0)" })
        }
        // Omitted rather than zeroed when absent: a resting heart rate of 0
        // would read as a medical emergency.
        if let sleepHours { lines.append("Sleep last night: \(String(format: "%.1f", sleepHours))h.") }
        if let restingHeartRate { lines.append("Resting HR: \(Int(restingHeartRate))bpm.") }
        if let hrv { lines.append("HRV: \(Int(hrv))ms.") }
        lines.append("Zones: \(zoneTable)")
        return lines.joined(separator: "\n")
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The much smaller payload sent at a walk break.
struct LiveCoachContext: Equatable, Sendable {
    var elapsedSeconds: TimeInterval
    var distanceKm: Double
    var splitPaces: [String]
    var timeInZoneSeconds: [String: TimeInterval]
    var currentZone: String?
    var currentHeartRate: Double?
    var walkBreakNumber: Int

    var promptSummary: String {
        var lines: [String] = []
        lines.append("\(formatDuration(elapsedSeconds)) elapsed, \(String(format: "%.2f", distanceKm))km covered.")
        if !splitPaces.isEmpty {
            lines.append("Splits so far: \(splitPaces.joined(separator: ", "))")
        }
        let zones = HRZone.table
            .compactMap { zone -> String? in
                guard let seconds = timeInZoneSeconds[zone.id], seconds > 0 else { return nil }
                return "\(zone.id) \(formatPace(seconds))"
            }
        if !zones.isEmpty { lines.append("Time in zone: \(zones.joined(separator: ", "))") }
        if let currentZone, let currentHeartRate {
            lines.append("Right now: \(Int(currentHeartRate))bpm, \(currentZone).")
        }
        lines.append("This is walk break \(walkBreakNumber).")
        return lines.joined(separator: "\n")
    }
}

/// Assembles a `CoachContext` from the plan and whatever history is available.
///
/// Everything except the plan is optional: a context missing recovery data is
/// still worth sending, and blocking a run's coaching on a HealthKit read that
/// might be slow would defeat the point.
enum CoachContextBuilder {
    @MainActor
    static func build(planDay: PlanDay?, runs: [HistoricRun] = [], asOf date: Date = Date()) -> CoachContext? {
        guard let plan = try? PlanStore.loadBundled() else { return nil }
        let progress = blockProgress(plan: plan, runs: runs, asOf: date)
        let day = planDay ?? plan.day(on: date)

        let zoneTable = HRZone.table
            .map { "\($0.id) \($0.lowerBPM)-\($0.upperBPM)" }
            .joined(separator: ", ")

        let recent = runs.prefix(3).map { run in
            let pace = run.paceSecPerKm.map { "\(formatPace($0))/km" } ?? "unknown pace"
            let bpm = run.averageHeartRate.map { "avg \(Int($0))bpm" } ?? "no HR"
            let zone = run.zone.map { " (\($0.id))" } ?? ""
            return "\(TrainingPlan.dayKey(for: run.date)): \(String(format: "%.1f", run.distanceKm))km at \(pace), \(bpm)\(zone)"
        }

        return CoachContext(
            sessionTitle: day?.title ?? "Run",
            sessionNotes: day?.notes ?? "",
            targetKm: day?.targetKm ?? 5,
            targetZone: day?.zone ?? "Z2",
            runWalk: day?.runWalk.map { "run \(Int($0.runMin))min / walk \(Int($0.walkMin))min" },
            daysToRace: progress?.daysToRace ?? plan.daysToRace(from: date),
            weekIndex: progress?.weekIndex ?? 0,
            totalWeeks: progress?.totalWeeks ?? 8,
            weekFocus: progress?.weekFocus ?? "",
            weekCompletedKm: progress?.completedKm ?? 0,
            weekPlannedKm: progress?.plannedKm ?? 0,
            easyShare: progress?.easyShare,
            recentRuns: Array(recent),
            sleepHours: nil,
            restingHeartRate: nil,
            hrv: nil,
            zoneTable: zoneTable
        )
    }
}
