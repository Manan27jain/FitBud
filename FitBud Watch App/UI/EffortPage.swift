import SwiftUI

/// Page 1, the default. Heart rate and zone at a glance, with the run/walk
/// interval draining around them.
struct EffortPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

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

                Text(state.currentZone.map { "\($0.id) \($0.name.uppercased())" } ?? "NO ZONE")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.currentZone?.color ?? .secondary)

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
