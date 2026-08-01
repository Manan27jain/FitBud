import SwiftUI

struct SummaryView: View {
    let workout: CompletedWorkout
    /// Seconds per zone, keyed by `HRZone.id`. Ours, not HealthKit's.
    let timeInZone: [String: TimeInterval]
    /// Non-nil when the run could not be saved to HealthKit. The numbers below
    /// are then reconstructed from live state rather than read back from Health.
    let errorMessage: String?
    let onDone: () -> Void

    private var shares: [ZoneShare] { zoneShares(timeInZone: timeInZone) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: -2) {
                    Text(String(format: "%.2f", workout.distanceMeters / 1000))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("KILOMETRES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(formatDuration(workout.duration))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.elapsedYellow)

                if !shares.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TIME IN ZONE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ZoneBreakdownBar(timeInZone: timeInZone, height: 10)
                        ForEach(shares, id: \.zone.id) { share in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(share.zone.color)
                                    .frame(width: 7, height: 7)
                                Text(share.zone.id)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(formatDuration(share.seconds))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text("\(Int((share.fraction * 100).rounded()))%")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                statRow("Avg pace", workout.averagePaceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
                statRow("Avg HR", workout.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
                statRow("Energy", "\(Int(workout.activeEnergyKcal)) kcal")

                if !workout.splits.isEmpty {
                    Text("SPLITS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(workout.splits, id: \.index) { split in
                        VStack(alignment: .leading, spacing: 2) {
                            statRow("km \(split.index)", formatPace(split.paceSecPerKm))
                            // Bars scaled against the athlete's own slowest
                            // kilometre, so a fade or a surge is visible without
                            // comparing six numbers to each other.
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(splitColor(split))
                                    .frame(width: geometry.size.width * (split.paceSecPerKm / slowestPace))
                            }
                            .frame(height: 3)
                        }
                    }
                }

                Button("New run", action: onDone)
                    .font(.footnote)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Done")
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    /// The slowest split sets the full bar width.
    private var slowestPace: Double {
        max(workout.splits.map(\.paceSecPerKm).max() ?? 1, 1)
    }

    /// Colour each split by the zone its heart rate landed in, so the split list
    /// doubles as a record of where the effort went.
    private func splitColor(_ split: Split) -> Color {
        guard let bpm = split.heartRateAtSplit, let zone = HRZone.zone(for: bpm) else {
            return .white.opacity(0.35)
        }
        return zone.color
    }
}
