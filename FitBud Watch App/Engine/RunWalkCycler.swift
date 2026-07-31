import Foundation

enum RunWalkPhase: Equatable, Sendable {
    case run
    case walk
}

/// Run/walk intervals expressed as a pure function of elapsed time.
///
/// Stateless by design: a dropped or delayed update can never desynchronise the
/// cycle, because the phase is always recomputed from the clock rather than
/// advanced step by step.
struct RunWalkCycler: Equatable, Sendable {
    let runSeconds: TimeInterval
    let walkSeconds: TimeInterval

    var cycleSeconds: TimeInterval { runSeconds + walkSeconds }

    func phase(at elapsed: TimeInterval) -> RunWalkPhase {
        positionInCycle(at: elapsed) < runSeconds ? .run : .walk
    }

    func remainingInPhase(at elapsed: TimeInterval) -> TimeInterval {
        let position = positionInCycle(at: elapsed)
        return position < runSeconds ? runSeconds - position : cycleSeconds - position
    }

    private func positionInCycle(at elapsed: TimeInterval) -> TimeInterval {
        guard cycleSeconds > 0 else { return 0 }
        return elapsed.truncatingRemainder(dividingBy: cycleSeconds)
    }
}
