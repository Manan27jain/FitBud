import SwiftUI

struct SummaryView: View {
    let workout: CompletedWorkout
    /// Non-nil when the run could not be saved to HealthKit. The numbers below
    /// are then reconstructed from live state rather than read back from Health.
    let errorMessage: String?
    let onDone: () -> Void

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Without this the app records exactly one workout per launch.
            // It sits at the top because the rows below it are unbounded — a
            // 10km run adds ten split rows — and the way off this screen must
            // not be a long crown-scroll away with tired hands.
            Button("New run", action: onDone)
                .font(.footnote)

            row("Distance", String(format: "%.2f km", workout.distanceMeters / 1000))
            row("Time", formatDuration(workout.duration))
            row("Avg pace", workout.averagePaceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
            row("Avg HR", workout.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
            row("Energy", "\(Int(workout.activeEnergyKcal)) kcal")

            if !workout.splits.isEmpty {
                Section("Splits") {
                    ForEach(workout.splits, id: \.index) { split in
                        row("km \(split.index)", formatPace(split.paceSecPerKm))
                    }
                }
            }
        }
        .navigationTitle("Done")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.footnote)
    }
}
