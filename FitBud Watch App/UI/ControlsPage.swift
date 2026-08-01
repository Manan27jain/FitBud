import SwiftUI

/// Page 0, one crown turn *up* from Effort — the vertical analogue of Apple
/// putting workout controls to the left of the metrics.
struct ControlsPage: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Button {
                Task {
                    model.phase == .paused ? await model.resume() : await model.pause()
                }
            } label: {
                Label(
                    model.phase == .paused ? "Resume" : "Pause",
                    systemImage: model.phase == .paused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(.orange)

            Button {
                Task { await model.end() }
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Controls")
    }
}
