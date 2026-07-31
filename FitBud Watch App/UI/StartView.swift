import SwiftUI

struct StartView: View {
    let model: WorkoutSessionModel
    @State private var authorization = HealthAuthorization()
    @State private var didRequestAccess = false

    private let options: [WorkoutConfiguration] = [
        .openEasyRun, .longRun4to1, .longRun5to1
    ]

    var body: some View {
        List {
            ForEach(options, id: \.title) { option in
                Button(option.title) {
                    Task { await model.start(option) }
                }
            }
            NavigationLink("Health history probe") {
                HistoryProbeView()
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("FitBud")
        .task {
            guard !didRequestAccess else { return }
            didRequestAccess = true
            try? await authorization.requestPermissions()
        }
    }
}
