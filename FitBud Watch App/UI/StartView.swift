import SwiftUI

struct StartView: View {
    let model: WorkoutSessionModel
    @State private var authorization = HealthAuthorization()
    @State private var didRequestAccess = false
    @State private var authorizationMessage: String?

    private let options: [WorkoutConfiguration] = [
        .openEasyRun, .longRun4to1, .longRun5to1
    ]

    var body: some View {
        List {
            // Above the session buttons, not below them: on a 46mm screen only
            // about three rows are visible, so a refusal to start rendered at
            // the bottom of the list is a message the athlete never sees.
            if let message = model.errorMessage ?? authorizationMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            ForEach(options, id: \.title) { option in
                Button(option.title) {
                    Task { await model.start(option) }
                }
            }
            NavigationLink("Health history probe") {
                HistoryProbeView()
            }
#if DEBUG
            Button("Demo run (scripted HR)") {
                Task { await model.startDemo() }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
#endif
        }
        .navigationTitle("FitBud")
        .task {
            guard !didRequestAccess else { return }
            didRequestAccess = true
            do {
                try await authorization.requestPermissions()
            } catch {
                // Swallowing this hid the one case where nothing will ever
                // work. Note that a *granted* request and a *denied* one both
                // succeed here — whether workouts can actually be saved is
                // checked in the recorder, immediately before starting.
                authorizationMessage = "Health access failed: \(error.localizedDescription)"
            }
        }
    }
}
