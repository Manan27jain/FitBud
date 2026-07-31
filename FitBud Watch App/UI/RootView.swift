import SwiftUI

struct RootView: View {
    @State private var model = WorkoutSessionModel()

    var body: some View {
        NavigationStack {
            switch model.phase {
            case .idle:
                StartView(model: model)
            case .running, .paused:
                LiveWorkoutView(model: model)
            case let .finished(workout):
                SummaryView(workout: workout)
            }
        }
    }
}
