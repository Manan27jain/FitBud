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
    /// Whole-percent labels, positionally aligned with `shares`, that sum to
    /// exactly 100 — see `zonePercentages` for why rounding each row
    /// independently can't be trusted to do that.
    private var percentages: [Int] { zonePercentages(shares) }

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
                    CaptionLabel("KILOMETRES")
                }

                Text(formatDuration(workout.duration))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.elapsedYellow)

                if !shares.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        CaptionLabel("TIME IN ZONE")
                        ZoneBreakdownBar(timeInZone: timeInZone, height: 10)
                        ForEach(Array(zip(shares, percentages)), id: \.0.zone.id) { share, percentage in
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
                                Text("\(percentage)%")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                statRow(workout.averagePaceSecPerKm.map(formatPace) ?? "--:--", ["AVG PACE", "/KM"])
                statRow(workout.averageHeartRate.map { "\(Int($0))" } ?? "--", ["AVERAGE", "HR"])
                statRow("\(Int(workout.activeEnergyKcal))", ["ACTIVE", "KCAL"])

                if !workout.splits.isEmpty {
                    CaptionLabel("SPLITS")
                    ForEach(workout.splits, id: \.index) { split in
                        VStack(alignment: .leading, spacing: 2) {
                            statRow(formatPace(split.paceSecPerKm), ["KM \(split.index)"])
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

    /// Number-led, caption to the right, exactly as the five live pages read.
    /// These rows used to be the one surface in the app that inverted Apple's
    /// grammar — a Title Case label on the left and the value pushed to the
    /// right margin — which meant the eye had to change direction between the
    /// hero numbers above and the stats below them.
    private func statRow(_ value: String, _ label: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            CaptionLabel(label)
            Spacer(minLength: 0)
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
