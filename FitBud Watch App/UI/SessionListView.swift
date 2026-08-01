import SwiftUI

/// Every session type, for when the athlete wants something other than what the
/// plan prescribes today. Reached from the home screen, so it gets a back button
/// from the enclosing `NavigationStack` for free.
struct SessionListView: View {
    let model: WorkoutSessionModel

    private let options: [WorkoutConfiguration] = [
        .openEasyRun, .longRun4to1, .longRun5to1
    ]

    var body: some View {
        List {
            ForEach(options, id: \.title) { option in
                Button {
                    Task { await model.start(option) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(subtitle(for: option))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Sessions")
    }

    /// Spells out the run/walk ratio so the two long-run options are
    /// distinguishable at a glance rather than by remembering which is which.
    private func subtitle(for configuration: WorkoutConfiguration) -> String {
        guard let runWalk = configuration.runWalk else { return "Continuous · Zone 2" }
        return "Run \(Int(runWalk.runSeconds / 60)) min · walk \(Int(runWalk.walkSeconds / 60)) min"
    }
}
