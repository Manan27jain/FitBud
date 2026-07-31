import Foundation
import WatchKit

enum WorkoutHaptic: Equatable, Sendable {
    case splitCompleted
    case startRunning
    case startWalking
    case workoutComplete
}

/// Which haptic, if any, an event deserves. Block changes are silent because a
/// structured session would otherwise buzz constantly during intervals.
func haptic(for event: WorkoutEvent) -> WorkoutHaptic? {
    switch event {
    case .splitCompleted:
        return .splitCompleted
    case let .phaseChanged(phase):
        return phase == .run ? .startRunning : .startWalking
    case .blockChanged:
        return nil
    case .finished:
        return .workoutComplete
    }
}

protocol HapticPlaying {
    func play(_ haptic: WorkoutHaptic)
}

struct WatchHaptics: HapticPlaying {
    func play(_ haptic: WorkoutHaptic) {
        let type: WKHapticType = switch haptic {
        case .splitCompleted: .notification
        case .startRunning: .start
        case .startWalking: .stop
        case .workoutComplete: .success
        }
        WKInterfaceDevice.current().play(type)
    }
}
