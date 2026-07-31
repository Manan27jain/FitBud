import Testing
@testable import FitBud_Watch_App

struct DurationFormattingTests {
    @Test func durationUnderAMinute() {
        #expect(formatDuration(45) == "0:45")
    }

    @Test func durationAtExactlyOneHour() {
        #expect(formatDuration(3600) == "1:00:00")
    }

    @Test func durationPastOneHourRollsOverForTheRaceCase() {
        // 2h35m33s — a real half-marathon finish time. The old formatter
        // rendered this as "155:33".
        #expect(formatDuration(9333) == "2:35:33")
    }

    @Test func durationPadsMinutesToTwoDigits() {
        #expect(formatDuration(65) == "1:05")
    }

    @Test func durationPadsSecondsToTwoDigits() {
        #expect(formatDuration(187) == "3:07")
    }

    @Test func paceKeepsShortFormForATypicalRunningPace() {
        #expect(formatPace(454) == "7:34")
    }

    @Test func paceNeverRollsOverToHours() {
        // Pace is seconds per kilometre; unlike duration it should never
        // grow an hour component, even for a slow value.
        #expect(formatPace(3600) == "60:00")
    }
}
