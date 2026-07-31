import Foundation
import WatchKit

enum WorkoutHaptic: Hashable, Sendable {
    case splitCompleted
    case startRunning
    case startWalking
    case blockChanged
    case workoutComplete
}

/// Which haptic an event deserves. Every event gets one, and the four are
/// deliberately distinguishable on the wrist: blocks are how the athlete knows
/// an interval has begun or ended without looking at the watch. Interval
/// sessions are coarse — the plan's 10min warmup + 5×(3min/2min) + 10min
/// cooldown is 12 blocks over 45 minutes, so 11 buzzes across a whole session.
func haptic(for event: WorkoutEvent) -> WorkoutHaptic {
    switch event {
    case .splitCompleted:
        return .splitCompleted
    case let .phaseChanged(phase):
        return phase == .run ? .startRunning : .startWalking
    case .blockChanged:
        return .blockChanged
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
        // Distinct from both the split notification and the run/walk
        // start/stop pair, so the three read differently through a sleeve.
        case .blockChanged: .directionUp
        case .workoutComplete: .success
        }
        WKInterfaceDevice.current().play(type)
    }
}
