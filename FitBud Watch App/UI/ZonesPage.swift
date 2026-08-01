import SwiftUI

/// Page 2, in Apple's Heart Rate Zones idiom: the segmented ladder, then
/// number-led rows with tiny uppercase labels stacked to their right.
struct ZonesPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDuration(state.elapsed))
                .font(Theme.elapsedFont)
                .monospacedDigit()
                .foregroundStyle(Theme.elapsedYellow)

            zoneLadder

            metric(
                value: state.heartRate.map { "\(Int($0))" } ?? "--",
                unit: "♥",
                label: nil
            )
            metric(
                // With no current zone there is no "time in zone" to report,
                // and `?? ""` used to look one up under an empty key and print
                // a confident 0:00 — during warm-up, and any time the sensor
                // drops out mid-run, which is exactly when a wrong zero is
                // most likely to be believed.
                value: state.currentZone.map { formatDuration(state.timeInZone[$0.id] ?? 0) } ?? "--",
                unit: nil,
                label: ["TIME", "IN ZONE"]
            )
            metric(
                value: state.averageHeartRate.map { "\(Int($0))" } ?? "--",
                unit: "BPM",
                label: ["AVERAGE", "HR"]
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .containerBackground(Theme.pageWash(Theme.zonesTint), for: .tabView)
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
                    .frame(height: 18)
                    .frame(maxWidth: isActive ? .infinity : 18)
                    .overlay {
                        if isActive {
                            Text("♥ \(zone.id)")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.black)
                        }
                    }
            }
        }
    }

    private func metric(value: String, unit: String?, label: [String]?) -> some View {
        // Apple's `137BPM AVERAGE HR`: the unit sits tight against its number
        // and the label stands off a little further, so "BPM" and "AVERAGE"
        // read as two things rather than one run-on phrase now that they share
        // a size.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(Theme.captionFont)
                    .foregroundStyle(unit == "♥" ? .red : .secondary)
                    .padding(.leading, 3)
            }
            if let label {
                CaptionLabel(label)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
    }
}
