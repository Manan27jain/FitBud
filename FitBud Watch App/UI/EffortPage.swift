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
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    // A box big enough for three digits, claimed before the
                    // first sample lands. "--" is narrower than "148", so
                    // without this the hero — and the zone label and countdown
                    // stacked under it — re-centre themselves the moment the
                    // heart rate arrives, 5–15 seconds into every single run.
                    .frame(width: 100, height: 50)

                Text(zoneLabelText)
                    .font(Theme.captionFont)
                    .foregroundStyle(zoneLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // The phase ring's start cap sits at the lower left at
                    // exactly this height and in exactly this colour, so a
                    // label wide enough to reach it loses its leading "Z" into
                    // the ring — "Z4 THRESHOLD" read as "4 THRESHOLD". Keep
                    // the label inside the ring's clear chord instead.
                    .frame(width: 100)

                if let phase = state.runWalkPhase, let remaining = state.phaseRemaining {
                    Text("\(phase == .run ? "RUN" : "WALK") \(formatPace(remaining))")
                        .font(Theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Effort")
    }
}
