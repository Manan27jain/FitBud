import SwiftUI

/// One week of the block, day by day.
struct PlanWeekDetailView: View {
    let week: PlanWeek
    let runs: [HistoricRun]
    let model: WorkoutSessionModel
    let today: Date

    private var todayKey: String { TrainingPlan.dayKey(for: today) }

    var body: some View {
        List {
            ForEach(week.days, id: \.date) { day in
                NavigationLink {
                    PlanDayDetailView(day: day, runs: runs, model: model, today: today)
                } label: {
                    row(for: day)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle(week.index == 0 ? "Bridge" : "Week \(week.index)")
    }

    @ViewBuilder private func row(for day: PlanDay) -> some View {
        let completed = run(on: day, from: runs)
        let isToday = day.date == todayKey

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(day.dow.uppercased())
                    .font(Theme.captionFont)
                    .foregroundStyle(isToday ? Color.green : Color.secondary)
                if isToday {
                    Text("TODAY")
                        .font(Theme.captionFont)
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
                if let completed {
                    // The tick answers "did I do it"; the dot's colour answers
                    // "was it easy", which is the rule the whole plan turns on.
                    Circle()
                        .fill(completed.zone?.color ?? .gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            Text(day.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(day.isRunningSession ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = detail(for: day) {
                Text(detail)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The planned shape of the day, or what was actually run once there is a
    /// recording to report instead.
    private func detail(for day: PlanDay) -> String? {
        if let completed = run(on: day, from: runs) {
            let pace = completed.paceSecPerKm.map { " · \(formatPace($0))/km" } ?? ""
            return String(format: "%.1f km", completed.distanceKm) + pace
        }
        var parts: [String] = []
        if day.targetKm > 0 { parts.append(String(format: "%.0f km", day.targetKm)) }
        else if day.targetMin > 0 { parts.append("\(Int(day.targetMin)) min") }
        if let zone = day.zone { parts.append(zone) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
