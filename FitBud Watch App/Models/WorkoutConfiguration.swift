import Foundation

/// What to record. Stage 2 will map a `PlanDay` onto this.
struct WorkoutConfiguration: Equatable, Sendable {
    let title: String
    let segments: [WorkoutSegment]
    let runWalk: RunWalkCycler?

    /// An unstructured easy run — the default when no plan is loaded.
    static let openEasyRun = WorkoutConfiguration(
        title: "Easy run",
        segments: [.openEnded(zone: "Z2", label: "Easy")],
        runWalk: nil
    )

    /// A long run with 4:1 run/walk, the plan's staple through week 4.
    static let longRun4to1 = WorkoutConfiguration(
        title: "Long run 4:1",
        segments: [.openEnded(zone: "Z2", label: "Long run")],
        runWalk: RunWalkCycler(runSeconds: 240, walkSeconds: 60)
    )

    /// A long run with 5:1 run/walk, used from week 5 and on race day.
    static let longRun5to1 = WorkoutConfiguration(
        title: "Long run 5:1",
        segments: [.openEnded(zone: "Z2", label: "Long run")],
        runWalk: RunWalkCycler(runSeconds: 300, walkSeconds: 60)
    )
}
