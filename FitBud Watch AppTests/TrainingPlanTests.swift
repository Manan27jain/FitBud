import Foundation
import Testing
@testable import FitBud_Watch_App

struct TrainingPlanTests {
    private func loadPlan() throws -> TrainingPlan {
        try PlanStore.loadBundled()
    }

    @Test func decodesTheRealBundledPlan() throws {
        let plan = try loadPlan()
        #expect(plan.planId == "half-2026-09-27")
        #expect(plan.goal.event == "Half Marathon")
        #expect(plan.goal.date == "2026-09-27")
        #expect(abs(plan.goal.distanceKm - 21.0975) < 0.0001)
        // Eight training weeks plus the bridge weekend.
        #expect(plan.weeks.count == 9)
        #expect(plan.weeks.first?.index == 0)
        #expect(plan.weeks.last?.index == 8)
    }

    @Test func everyDayOfTheBlockIsPresent() throws {
        let plan = try loadPlan()
        let days = plan.weeks.flatMap(\.days)
        #expect(days.count == 58)
    }

    @Test func findsTheSessionForAGivenCalendarDay() throws {
        let plan = try loadPlan()
        // 2026-08-04 is the week 1 Tuesday easy run.
        let day = plan.day(on: try date("2026-08-04"))
        #expect(day?.title == "Easy run")
        #expect(day?.targetKm == 4)
        #expect(day?.zone == "Z2")
        #expect(day?.runWalk?.runMin == 4)
        #expect(day?.runWalk?.walkMin == 1)
    }

    @Test func restDaysDecodeWithNoZoneAndNoRunWalk() throws {
        let plan = try loadPlan()
        let day = plan.day(on: try date("2026-08-03"))
        #expect(day?.type == "rest")
        #expect(day?.zone == nil)
        #expect(day?.runWalk == nil)
        #expect(day?.segments.isEmpty == true)
        #expect(day?.isRunningSession == false)
    }

    @Test func decodesWarmupAndRepeatSegments() throws {
        let plan = try loadPlan()
        // 2026-08-06 is the strides session: 5 min warmup then 4 strides.
        let day = plan.day(on: try date("2026-08-06"))
        #expect(day?.segments.count == 2)
        guard case let .warmup(minutes, zone, _)? = day?.segments.first else {
            Issue.record("expected a warmup segment"); return
        }
        #expect(minutes == 5)
        #expect(zone == "Z1")
        guard case let .repeatBlock(times, work, recover)? = day?.segments.last else {
            Issue.record("expected a repeat segment"); return
        }
        #expect(times == 4)
        #expect(work.zone == "Z5")
        #expect(recover.zone == "Z1")
    }

    @Test func decodesACooldownSegment() throws {
        let plan = try loadPlan()
        // 2026-08-20 is the week 3 tempo session, which has all three kinds.
        let day = plan.day(on: try date("2026-08-20"))
        let kinds = day?.segments.map { segment -> String in
            switch segment {
            case .warmup: "warmup"
            case .repeatBlock: "repeat"
            case .cooldown: "cooldown"
            }
        }
        #expect(kinds == ["warmup", "repeat", "cooldown"])
    }

    @Test func findsTheWeekContainingADate() throws {
        let plan = try loadPlan()
        let week = plan.week(containing: try date("2026-08-19"))
        #expect(week?.index == 3)
        #expect(week?.targetKm == 22)
    }

    @Test func countsDaysToRaceDay() throws {
        let plan = try loadPlan()
        #expect(plan.daysToRace(from: try date("2026-08-01")) == 57)
        #expect(plan.daysToRace(from: try date("2026-09-27")) == 0)
    }

    @Test func aDateOutsideTheBlockHasNoSession() throws {
        let plan = try loadPlan()
        #expect(plan.day(on: try date("2026-07-15")) == nil)
        #expect(plan.day(on: try date("2026-10-05")) == nil)
    }

    @Test func decodesTheProgressionCaps() throws {
        let plan = try loadPlan()
        #expect(plan.rules.progressionCaps.weeklyKmIncreaseMax == 0.2)
        #expect(plan.rules.progressionCaps.longRunIncreaseMaxKm == 2.0)
    }

    @Test func decodesTheImmutableRulesAsProse() throws {
        let plan = try loadPlan()
        // Four rules, kept as text: they are displayed to the athlete and
        // enforced in code, never parsed.
        #expect(plan.rules.immutable.count == 4)
        #expect(plan.rules.immutable.contains { $0.contains("Week 4 cutback") })
        #expect(plan.rules.immutable.contains { $0.contains("Long run never exceeds 16km") })
    }

    @Test func decodesTheZoneDisciplineRule() throws {
        let plan = try loadPlan()
        #expect(plan.rules.zoneDiscipline.contains("80%"))
    }

    @Test func exposesTheBlockStartDate() throws {
        let plan = try loadPlan()
        #expect(TrainingPlan.dayKey(for: try #require(plan.startDate)) == "2026-08-01")
    }

    private func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad date"))
        }
        return date
    }
}

struct PlanDayToConfigurationTests {
    private func day(_ isoDate: String) throws -> PlanDay {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let plan = try PlanStore.loadBundled()
        guard let date = formatter.date(from: isoDate), let day = plan.day(on: date) else {
            throw PlanStoreError.notBundled("day \(isoDate)")
        }
        return day
    }

    @Test func carriesTheTitleAcross() throws {
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-04"))
        #expect(configuration.title == "Easy run")
    }

    @Test func convertsRunWalkMinutesToSeconds() throws {
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-04"))
        #expect(configuration.runWalk?.runSeconds == 240)
        #expect(configuration.runWalk?.walkSeconds == 60)
    }

    @Test func aDayWithNoRunWalkHasNoCycler() throws {
        // Week 3's tempo session is structured but has no run/walk ratio.
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-20"))
        #expect(configuration.runWalk == nil)
    }

    @Test func anUnstructuredDayBecomesASingleOpenBlock() throws {
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-04"))
        #expect(configuration.segments.count == 1)
        guard case let .openEnded(zone, _) = configuration.segments[0] else {
            Issue.record("expected one open-ended segment"); return
        }
        #expect(zone == "Z2")
    }

    @Test func structuredDaysExpandAndKeepAnOpenBlockLast() throws {
        // 5 min warmup + repeat block (with 4 strides) + trailing open block.
        // The timeline will expand the repeat into 9 blocks total, plus the open.
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-06"))
        #expect(configuration.segments.count == 3)
        guard case .warmup = configuration.segments.first else {
            Issue.record("expected warmup first"); return
        }
        guard case .openEnded = configuration.segments.last else {
            Issue.record("expected an open-ended block last"); return
        }
    }

    @Test func repeatBlocksSurviveAsRepeatBlocks() throws {
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-20"))
        let repeats = configuration.segments.filter { segment in
            if case .repeatBlock = segment { return true }
            return false
        }
        #expect(repeats.count == 1)
    }

    @Test func aRestDayStillProducesAUsableConfiguration() throws {
        // The UI won't offer it, but constructing one must not crash.
        let configuration = WorkoutConfiguration(planDay: try day("2026-08-03"))
        #expect(configuration.segments.count == 1)
        #expect(configuration.runWalk == nil)
    }
}
