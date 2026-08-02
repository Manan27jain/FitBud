import SwiftUI

/// The whole block, one row per week.
///
/// The home screen can only answer "what am I doing today". This answers "what
/// does the rest of this look like", which is the question an athlete eight
/// weeks out from a race actually asks.
struct PlanWeekListView: View {
    let plan: TrainingPlan
    let runs: [HistoricRun]
    let model: WorkoutSessionModel
    let today: Date

    private var currentWeekIndex: Int? { plan.week(containing: today)?.index }

    var body: some View {
        List {
            ForEach(plan.weeks, id: \.index) { week in
                NavigationLink {
                    PlanWeekDetailView(week: week, runs: runs, model: model, today: today)
                } label: {
                    row(for: week)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Plan")
    }

    @ViewBuilder private func row(for week: PlanWeek) -> some View {
        let completion = weekCompletion(week: week, runs: runs)
        let isCurrent = week.index == currentWeekIndex

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title(for: week))
                    .font(Theme.captionFont)
                    // The only colour on the row, so "where am I" is answerable
                    // without reading a single number.
                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                Spacer(minLength: 0)
                Text(String(format: "%.1f km", week.targetKm))
                    .font(Theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(week.focus)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            // Only weeks with something recorded get a bar. An empty track on
            // all six future weeks would read as "you have failed these".
            if completion.completedSessions > 0 {
                ProgressTrack(fraction: completion.volumeFraction)
                Text(String(
                    format: "%.1f / %.0f km · %d of %d",
                    completion.completedKm, completion.plannedKm,
                    completion.completedSessions, completion.plannedSessions
                ))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Week 0 is the two-day calibration bridge, not a numbered training week —
    /// calling it "Week 0" reads as an off-by-one error.
    private func title(for week: PlanWeek) -> String {
        week.index == 0 ? "BRIDGE" : "WEEK \(week.index)"
    }
}
