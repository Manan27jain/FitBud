#if DEBUG
import Foundation

/// Returns a canned brief instantly so the coaching UI can be driven on a
/// simulator with no network and no API spend.
struct DemoAIProvider: AIProviding {
    let id: ProviderID = .openAI

    func brief(context: CoachContext) async throws -> SessionBrief {
        SessionBrief(
            opening: "Easy today. Let the walk breaks do the work.",
            rules: [
                // `DemoWorkoutRecorder.fadeWindow` is placed in the sweep's
                // low-HR stretch, so this doesn't compete with `zoneAbove`
                // for the single immediate-cue slot; listed first anyway as
                // cheap insurance if that ever changes.
                CueRule(trigger: .paceFading(percentSlower: 12, sustainedSec: 15),
                        message: "Pace is fading. Relax your shoulders and hold on.",
                        urgency: .immediate, repeats: true),
                CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 20),
                        message: "Above easy. Ease off and let it settle.",
                        urgency: .immediate, repeats: true),
                CueRule(trigger: .phaseStarted(.walk), message: "Walk break. Breathe.", repeats: true),
                CueRule(trigger: .splitCompleted(index: nil), message: "Another kilometre down.", repeats: true),
                CueRule(trigger: .halfway, message: "Halfway. Still feeling easy?")
            ]
        )
    }

    func liveCue(context: LiveCoachContext) async throws -> String {
        try? await Task.sleep(for: .milliseconds(400))
        return "Splits are steady. Keep this rhythm."
    }

    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
        WorkoutAnalysis(
            summary: "Steady run, mostly in Z2. That is exactly the assignment.",
            takeaway: "Start the next one thirty seconds slower."
        )
    }
}
#endif
