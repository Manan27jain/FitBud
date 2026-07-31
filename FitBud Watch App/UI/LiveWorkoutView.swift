import SwiftUI

struct LiveWorkoutView: View {
    let model: WorkoutSessionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDuration(model.state.elapsed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                HStack {
                    Text(String(format: "%.2f km", model.state.distanceKm))
                    Spacer()
                    Text(model.state.heartRate.map { "\(Int($0)) bpm" } ?? "-- bpm")
                }
                .font(.system(size: 16, weight: .medium))

                Text(paceText)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                if let phase = model.state.runWalkPhase, let remaining = model.state.phaseRemaining {
                    Text("\(phase == .run ? "RUN" : "WALK") \(Int(remaining))s")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(phase == .run ? .green : .orange)
                }

                if let block = model.state.currentBlock, block.kind != .open {
                    Text(block.label).font(.footnote).foregroundStyle(.secondary)
                }

                Spacer()

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                HStack {
                    Button(model.phase == .paused ? "Resume" : "Pause") {
                        Task {
                            model.phase == .paused ? await model.resume() : await model.pause()
                        }
                    }
                    Button("End") { Task { await model.end() } }
                        .tint(.red)
                }
                .font(.footnote)
            }
            .padding(.horizontal, 8)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var paceText: String {
        guard let pace = model.state.averagePaceSecPerKm else { return "--:--/km" }
        return "\(formatPace(pace))/km"
    }
}
