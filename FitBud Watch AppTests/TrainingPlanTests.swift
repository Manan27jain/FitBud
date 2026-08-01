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
