import Foundation
import Testing
@testable import FitBud_Watch_App

struct BlockProgressTests {
    private func plan() throws -> TrainingPlan { try PlanStore.loadBundled() }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    private func run(_ isoDate: String, km: Double, bpm: Double?) -> HistoricRun {
        HistoricRun(
            id: UUID(),
            date: date(isoDate),
            distanceMeters: km * 1000,
            duration: km * 540,
            averageHeartRate: bpm
        )
    }

    @Test func reportsTheWeekAndCountdown() throws {
        let progress = blockProgress(plan: try plan(), runs: [], asOf: date("2026-08-05"))
        #expect(progress?.weekIndex == 1)
        #expect(progress?.totalWeeks == 8)
        #expect(progress?.daysToRace == 53)
        #expect(progress?.weekFocus == "Reset the effort. Learn to run slow.")
        #expect(progress?.plannedKm == 16)
    }

    @Test func countsOnlyRunsInsideTheCurrentWeek() throws {
        let runs = [
            run("2026-08-04", km: 4, bpm: 155),   // in week 1
            run("2026-08-09", km: 8, bpm: 158),   // in week 1
            run("2026-07-28", km: 5, bpm: 160)    // before the block
        ]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(progress?.completedKm == 12)
        #expect(progress?.completedSessions == 2)
    }

    @Test func plannedSessionsExcludeRestStrengthAndCrossTraining() throws {
        // Week 1 has three running days: Tue easy, Thu easy+strides, Sun long.
        let progress = blockProgress(plan: try plan(), runs: [], asOf: date("2026-08-05"))
        #expect(progress?.plannedSessions == 3)
    }

    @Test func easyShareIsTheFractionOfRunsAveragingZoneOneOrTwo() throws {
        let runs = [
            run("2026-08-04", km: 4, bpm: 155),   // Z2 — easy
            run("2026-08-06", km: 4, bpm: 140),   // Z1 — easy
            run("2026-08-09", km: 8, bpm: 186)    // Z4 — not easy
        ]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(abs((progress?.easyShare ?? 0) - (2.0 / 3.0)) < 0.0001)
    }

    @Test func easyShareIsNilWithNoRunsToJudge() throws {
        let progress = blockProgress(plan: try plan(), runs: [], asOf: date("2026-08-05"))
        #expect(progress?.easyShare == nil)
    }

    /// The flagship number of the redesign used to call the easiest possible
    /// run "too hard". `HRZone.zone(for:)` returns nil below 133 bpm as well as
    /// when there is no heart rate, and `isEasy` treated both as not-easy — so
    /// a recovery jog averaging 130 printed "Too hard. Slow down and let the
    /// walk breaks work." at the athlete.
    @Test func aRunBelowZoneOneIsEasierThanEasy() throws {
        let runs = [run("2026-08-04", km: 4, bpm: 130)]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(progress?.easyShare == 1)
    }

    /// The boundary itself: 133 is Z1's floor and belongs to Z1, 132.9 is below
    /// the table entirely. Both are easy, by different routes through `isEasy`.
    @Test func bothSidesOfZoneOnesFloorAreEasy() throws {
        let runs = [
            run("2026-08-04", km: 4, bpm: 132.9),
            run("2026-08-06", km: 4, bpm: 133)
        ]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(progress?.easyShare == 1)
    }

    @Test func runsWithoutAHeartRateDoNotCountAsEasy() throws {
        // A run with no HR tells us nothing about effort; counting it as easy
        // would flatter the number the whole plan is judged on.
        let runs = [run("2026-08-04", km: 4, bpm: nil)]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(progress?.easyShare == 0)
    }

    @Test func volumeFractionIsCappedAtOne() throws {
        let runs = [run("2026-08-04", km: 40, bpm: 155)]
        let progress = blockProgress(plan: try plan(), runs: runs, asOf: date("2026-08-05"))
        #expect(progress?.volumeFraction == 1)
    }

    @Test func aDateOutsideTheBlockHasNoProgress() throws {
        #expect(blockProgress(plan: try plan(), runs: [], asOf: date("2026-06-01")) == nil)
    }
}

struct WeekCompletionTests {
    private func plan() throws -> TrainingPlan { try PlanStore.loadBundled() }

    private func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return try #require(formatter.date(from: string))
    }

    /// Named `historicRun`, not `run`, on purpose: a member called `run` would
    /// sit beside the global `run(on:from:)` these tests exercise, and leaving
    /// overload resolution to sort that out is a trap for whoever edits next.
    private func historicRun(_ isoDate: String, km: Double, hr: Double? = 155) throws -> HistoricRun {
        HistoricRun(
            id: UUID(),
            date: try date(isoDate),
            distanceMeters: km * 1000,
            duration: km * 540,          // 9:00/km
            averageHeartRate: hr
        )
    }

    @Test func matchesRunsToTheWeekThatContainsThem() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let matched = runs(in: week, from: [
            try historicRun("2026-08-04", km: 4),   // inside week 1
            try historicRun("2026-08-09", km: 8),   // inside week 1 (Sunday)
            try historicRun("2026-08-11", km: 5)    // week 2 — must not match
        ])
        #expect(matched.count == 2)
    }

    @Test func sumsCompletedVolumeAndSessionsForAWeek() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [
            try historicRun("2026-08-04", km: 4),
            try historicRun("2026-08-09", km: 8)
        ])
        #expect(abs(completion.completedKm - 12) < 0.0001)
        #expect(completion.completedSessions == 2)
        #expect(completion.plannedKm == 16)
        // Week 1 runs Tue easy 4km, Thu easy 4km, Sun long 8km.
        #expect(completion.plannedSessions == 3)
    }

    @Test func volumeFractionCapsAtOneOnAnOvershoot() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [try historicRun("2026-08-04", km: 40)])
        #expect(completion.volumeFraction == 1)
    }

    @Test func aWeekWithNoRunsCompletesNothing() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [])
        #expect(completion.completedKm == 0)
        #expect(completion.completedSessions == 0)
        #expect(completion.volumeFraction == 0)
    }

    @Test func findsTheRunRecordedOnASpecificDay() throws {
        let plan = try plan()
        let day = try #require(plan.day(on: try date("2026-08-04")))
        let matched = run(on: day, from: [
            try historicRun("2026-08-04", km: 4),
            try historicRun("2026-08-09", km: 8)
        ])
        #expect(abs((matched?.distanceKm ?? 0) - 4) < 0.0001)
    }

    @Test func aDayWithNoRunHasNoMatch() throws {
        let plan = try plan()
        let day = try #require(plan.day(on: try date("2026-08-03")))   // rest day
        #expect(run(on: day, from: [try historicRun("2026-08-04", km: 4)]) == nil)
    }

    @Test func effectivePlanReturnsTheBundledPlanForNow() throws {
        #expect(try PlanStore.effectivePlan().planId == "half-2026-09-27")
    }
}
