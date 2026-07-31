import SwiftUI

/// Page 2, in Apple's Heart Rate Zones idiom: the segmented ladder, then
/// number-led rows with tiny uppercase labels stacked to their right.
struct ZonesPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDuration(state.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.elapsedYellow)

            zoneLadder

            metric(
                value: state.heartRate.map { "\(Int($0))" } ?? "--",
                unit: "♥",
                label: nil
            )
            metric(
                value: formatDuration(state.timeInZone[state.currentZone?.id ?? ""] ?? 0),
                unit: nil,
                label: "TIME\nIN ZONE"
            )
            metric(
                value: state.averageHeartRate.map { "\(Int($0))" } ?? "--",
                unit: "BPM",
                label: "AVERAGE\nHR"
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Zones")
    }

    /// Five segments, with the active one widened to carry its caption — the
    /// ring cannot do this because widening would move its needle's frame of
    /// reference, but this bar has no needle to keep honest.
    private var zoneLadder: some View {
        HStack(spacing: 2) {
            ForEach(HRZone.table) { zone in
                let isActive = zone.id == state.currentZone?.id
                RoundedRectangle(cornerRadius: 3)
                    .fill(zone.color.opacity(isActive ? 1 : Theme.inactiveZoneOpacity))
                    .frame(height: 20)
                    .frame(maxWidth: isActive ? .infinity : 18)
                    .overlay {
                        if isActive {
                            Text("♥ \(zone.id)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                        }
                    }
            }
        }
    }

    private func metric(value: String, unit: String?, label: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(unit == "♥" ? .red : .secondary)
            }
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineSpacing(-2)
            }
            Spacer(minLength: 0)
        }
    }
}
