import SwiftUI

struct RootView: View {
    // Owned by `FitBudApp`, not here: see the comment there for why the
    // model's lifetime must be the process's rather than the scene's.
    let model: WorkoutSessionModel
    let settings: CoachSettings

    var body: some View {
        NavigationStack {
            switch model.phase {
            case .idle:
                HomeView(model: model, settings: settings)
            case .running, .paused:
                LiveWorkoutView(model: model)
            case let .finished(workout):
                SummaryView(
                    workout: workout,
                    timeInZone: model.finishedTimeInZone,
                    errorMessage: model.errorMessage,
                    onDone: { model.reset() }
                )
            }
        }
    }
}
