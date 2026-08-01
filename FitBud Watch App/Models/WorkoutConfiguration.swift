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

extension WorkoutConfiguration {
    /// Builds a recordable configuration from a day of the training plan.
    ///
    /// An open-ended block is always appended last. The plan's segments describe
    /// structure *within* a distance-based run — the strides session is a warmup
    /// and four strides inside a 4 km run — so without it the timeline would
    /// report the session complete after the final stride and the athlete would
    /// lose their block display mid-run. Placing it last keeps
    /// `SegmentTimeline`'s open-block short-circuit harmless.
    init(planDay day: PlanDay) {
        var segments: [WorkoutSegment] = []
        for segment in day.segments {
            switch segment {
            case let .warmup(minutes, zone, label):
                segments.append(.warmup(minutes: minutes, zone: zone, label: label))
            case let .cooldown(minutes, zone, label):
                segments.append(.cooldown(minutes: minutes, zone: zone, label: label))
            case let .repeatBlock(times, work, recover):
                segments.append(.repeatBlock(
                    times: times,
                    work: Interval(minutes: work.minutes, zone: work.zone, label: work.label),
                    recover: Interval(minutes: recover.minutes, zone: recover.zone, label: recover.label)
                ))
            }
        }
        segments.append(.openEnded(zone: day.zone ?? "Z2", label: day.title))

        self.init(
            title: day.title,
            segments: segments,
            runWalk: day.runWalk.map {
                RunWalkCycler(runSeconds: $0.runMin * 60, walkSeconds: $0.walkMin * 60)
            }
        )
    }
}
