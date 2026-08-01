import Foundation
import Testing
@testable import FitBud_Watch_App

struct CoachContextTests {
    private func sampleContext() -> CoachContext {
        CoachContext(
            sessionTitle: "Long run 5:1",
            sessionNotes: "Take the walk breaks from minute one.",
            targetKm: 14,
            targetZone: "Z2",
            runWalk: "run 5min / walk 1min",
            daysToRace: 53,
            weekIndex: 5,
            totalWeeks: 8,
            weekFocus: "Biggest jump of the block.",
            weekCompletedKm: 12,
            weekPlannedKm: 26,
            easyShare: 0.66,
            recentRuns: [
                "2026-08-04: 4.0km at 9:12/km, avg 158bpm (Z2)",
                "2026-08-06: 4.1km at 8:50/km, avg 171bpm (Z3)"
            ],
            sleepHours: 5.2,
            restingHeartRate: 66,
            hrv: 41,
            zoneTable: "Z1 133-148, Z2 148-163, Z3 163-177, Z4 177-192, Z5 192-207"
        )
    }

    @Test func promptSummaryNamesTheSessionAndTheTarget() {
        let text = sampleContext().promptSummary
        #expect(text.contains("Long run 5:1"))
        #expect(text.contains("14"))
        #expect(text.contains("Z2"))
    }

    @Test func promptSummaryCarriesRecoveryAndRaceCountdown() {
        let text = sampleContext().promptSummary
        #expect(text.contains("53"))
        #expect(text.contains("5.2"))
        #expect(text.contains("66"))
    }

    @Test func promptSummaryStatesTheEasyShareAsAPercentage() {
        // The 80% rule is the point of the whole plan; the model must see the
        // number in a form it will not misread as a fraction of one.
        #expect(sampleContext().promptSummary.contains("66%"))
    }

    @Test func missingRecoveryDataIsOmittedRatherThanSentAsZero() {
        // A zero resting heart rate would read as a medical emergency.
        var context = sampleContext()
        context.sleepHours = nil
        context.restingHeartRate = nil
        context.hrv = nil
        let text = context.promptSummary
        #expect(!text.contains("Sleep"))
        #expect(!text.contains("Resting HR"))
    }

    @Test func liveSummaryCarriesSplitsAndZoneTime() {
        let live = LiveCoachContext(
            elapsedSeconds: 1200,
            distanceKm: 3.2,
            splitPaces: ["9:05", "9:20", "8:58"],
            timeInZoneSeconds: ["Z1": 120, "Z2": 900, "Z3": 180],
            currentZone: "Z2",
            currentHeartRate: 156,
            walkBreakNumber: 4,
            recentPaceSecPerKm: nil
        )
        let text = live.promptSummary
        #expect(text.contains("9:20"))
        #expect(text.contains("Z2"))
        #expect(text.contains("3.2"))
    }

    @Test func liveSummaryCarriesTheRecentPaceWhenPresent() {
        let live = LiveCoachContext(
            elapsedSeconds: 1200,
            distanceKm: 3.2,
            splitPaces: [],
            timeInZoneSeconds: [:],
            currentZone: nil,
            currentHeartRate: nil,
            walkBreakNumber: 1,
            recentPaceSecPerKm: 675
        )
        #expect(live.promptSummary.contains("11:15"))
    }

    @Test func liveSummaryOmitsRecentPaceRatherThanSendingZero() {
        // A zero pace would read as standing still, or worse, as a
        // divide-by-zero the model can't make sense of.
        let live = LiveCoachContext(
            elapsedSeconds: 1200,
            distanceKm: 3.2,
            splitPaces: [],
            timeInZoneSeconds: [:],
            currentZone: nil,
            currentHeartRate: nil,
            walkBreakNumber: 1,
            recentPaceSecPerKm: nil
        )
        #expect(!live.promptSummary.contains("Recent pace"))
    }
}
