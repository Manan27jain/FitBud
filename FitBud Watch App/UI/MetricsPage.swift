import SwiftUI

/// Page 3. The classic four numbers, number-led with labels to the right.
struct MetricsPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatDuration(state.elapsed))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.elapsedYellow)

            row(String(format: "%.2f", state.distanceKm), "KM")
            row(state.averagePaceSecPerKm.map(formatPace) ?? "--:--", "/KM")
            row("\(Int(state.activeEnergyKcal))", "KCAL")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Metrics")
    }

    private func row(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
