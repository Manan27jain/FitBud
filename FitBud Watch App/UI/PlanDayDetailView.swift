import SwiftUI

/// One day of the plan in full: what it asks for, why, and a way to start it.
struct PlanDayDetailView: View {
    let day: PlanDay
    let runs: [HistoricRun]
    let model: WorkoutSessionModel

    private var completed: HistoricRun? { run(on: day, from: runs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let completed { completedCard(completed) }
                if !day.segments.isEmpty { segmentsCard }
                if !day.notes.isEmpty {
                    Text(day.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if day.isRunningSession { startButton }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(day.dow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.date)
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(day.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = plannedDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Target, zone with its real bpm range, and run/walk ratio — the same
    /// grammar the home screen's today card uses, so the two agree.
    private var plannedDetail: String? {
        var parts: [String] = []
        if day.targetKm > 0 { parts.append(String(format: "%.0f km", day.targetKm)) }
        if day.targetMin > 0 { parts.append("\(Int(day.targetMin)) min") }
        if let zone = day.zone, let hrZone = HRZone.table.first(where: { $0.id == zone }) {
            parts.append("\(zone) \(hrZone.lowerBPM)–\(hrZone.upperBPM) bpm")
        }
        if let runWalk = day.runWalk {
            parts.append("run \(Int(runWalk.runMin))′/walk \(Int(runWalk.walkMin))′")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func completedCard(_ completedRun: HistoricRun) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("COMPLETED")
                .font(Theme.captionFont)
                .foregroundStyle(.green)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", completedRun.distanceKm))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("KM")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(completedRun.paceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let heartRate = completedRun.averageHeartRate {
                Text("\(Int(heartRate)) bpm average · \(completedRun.zone?.name ?? "no zone")")
                    .font(.system(size: 10))
                    .foregroundStyle(completedRun.isEasy ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var segmentsCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("STRUCTURE")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            ForEach(Array(day.segments.enumerated()), id: \.offset) { _, segment in
                Text(describe(segment))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func describe(_ segment: PlanSegment) -> String {
        switch segment {
        case let .warmup(minutes, zone, _):
            "Warm up \(Int(minutes)) min · \(zone)"
        case let .cooldown(minutes, zone, _):
            "Cool down \(Int(minutes)) min · \(zone)"
        case let .repeatBlock(times, work, recover):
            "\(times) × \(Int(work.minutes)) min \(work.zone), \(Int(recover.minutes)) min \(recover.zone)"
        }
    }

    /// Any running session can be started, including a future one — the athlete
    /// may legitimately want to run Sunday's long run on Saturday, and the date
    /// is shown right above this button so the choice is informed.
    private var startButton: some View {
        Button {
            Task { await model.start(WorkoutConfiguration(planDay: day)) }
        } label: {
            Label(completed == nil ? "Start" : "Run it again", systemImage: "figure.run")
                .frame(maxWidth: .infinity)
        }
        .tint(HRZone.table.first { $0.id == day.zone }?.color ?? .green)
    }
}
