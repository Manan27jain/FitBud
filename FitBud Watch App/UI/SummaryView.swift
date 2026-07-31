import SwiftUI

struct SummaryView: View {
    let workout: CompletedWorkout

    var body: some View {
        List {
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
