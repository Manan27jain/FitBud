import SwiftUI

/// Page 1, the default. Heart rate and zone at a glance, with the run/walk
/// interval draining around them.
struct EffortPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    /// "NO ZONE" only when there's no heart-rate sample at all — genuinely
    /// no signal. Once a sample arrives but sits below Z1's floor (resting
    /// or early in a run), that's "WARMING UP", not absent: `currentZone`
    /// stays correctly `nil` from `HRZone.zone(for:)`, but the label and
    /// tint should read as alive rather than broken.
    private var zoneLabelText: String {
        if let zone = state.currentZone { return "\(zone.id) \(zone.name.uppercased())" }
        return state.heartRate != nil ? "WARMING UP" : "NO ZONE"
    }

    private var zoneLabelColor: Color {
        if let zone = state.currentZone { return zone.color }
        return state.heartRate != nil ? EffortRingView.warmingUpTint : .secondary
    }

    var body: some View {
        ZStack {
            EffortRingView(
                heartRate: state.heartRate,
                currentZone: state.currentZone,
                phaseRemainingFraction: state.phaseRemainingFraction,
                targetZoneID: state.currentBlock?.zone
            )

            VStack(spacing: 0) {
                Text(state.heartRate.map { "\(Int($0))" } ?? "--")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(zoneLabelText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(zoneLabelColor)

                if let phase = state.runWalkPhase, let remaining = state.phaseRemaining {
                    Text("\(phase == .run ? "RUN" : "WALK") \(formatPace(remaining))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Effort")
    }
}
