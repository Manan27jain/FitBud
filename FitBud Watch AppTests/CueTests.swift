import Foundation
import Testing
@testable import FitBud_Watch_App

struct SecretsTests {
    @Test func normaliseMissingKeyReturnsNil() {
        let values: [String: String] = [:]
        let result = Secrets.normalise(values, key: "NONEXISTENT")
        #expect(result == nil)
    }

    @Test func normaliseEmptyStringReturnsNil() {
        let values: [String: String] = ["KEY": ""]
        let result = Secrets.normalise(values, key: "KEY")
        #expect(result == nil)
    }

    @Test func normaliseWhitespaceOnlyReturnsNil() {
        let whitespace = String(repeating: " ", count: 10)
        let values: [String: String] = ["KEY": whitespace]
        let result = Secrets.normalise(values, key: "KEY")
        #expect(result == nil)
    }

    @Test func normaliseRealValueReturnsValue() {
        let values: [String: String] = ["KEY": "test-key-value"]
        let result = Secrets.normalise(values, key: "KEY")
        #expect(result == "test-key-value")
    }

    @Test func hasAnyKeyInvariant() {
        // Verify that hasAnyKey accurately reflects whether any key is configured.
        // Do not assert on actual key values to avoid leaking them on test failure.
        let hasOpenAI = Secrets.openAIKey != nil
        let hasGemini = Secrets.geminiKey != nil
        let expected = hasOpenAI || hasGemini
        #expect(Secrets.hasAnyKey == expected)
    }
}

struct CueRuleDecodingTests {
    private func decode(_ json: String) throws -> SessionBrief {
        try JSONDecoder().decode(SessionBrief.self, from: Data(json.utf8))
    }

    @Test func decodesAWellFormedBrief() throws {
        let brief = try decode("""
        {"opening":"Easy today. Let the walk breaks do the work.",
         "rules":[{"trigger":{"kind":"zoneAbove","zone":"Z2","sustainedSec":30},
                   "message":"Above easy. Ease off.","urgency":"immediate","repeats":true}]}
        """)
        #expect(brief.opening == "Easy today. Let the walk breaks do the work.")
        #expect(brief.rules.count == 1)
        #expect(brief.rules[0].trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30))
        #expect(brief.rules[0].urgency == .immediate)
        #expect(brief.rules[0].repeats)
    }

    @Test func rejectsAMessageLongerThanTwelveWords() {
        // Truncating mid-sentence would be worse than dropping the bundle:
        // a coach that stops speaking halfway through reads as broken.
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"halfway"},
             "message":"one two three four five six seven eight nine ten eleven twelve thirteen",
             "urgency":"atNextBreak","repeats":false}]}
            """)
        }
    }

    @Test func rejectsAnOpeningLongerThanTwelveWords() {
        // `CoachMessageView` shrinks an over-length line rather than
        // truncating it, but only up to a point: twelve words is what
        // actually fits three lines at 20pt on a 46mm screen. Unlike
        // `rules[].message`, nothing enforces that limit on `opening` at the
        // model level, and the system prompt only *asks* the model to keep
        // every message to twelve words — a model that ignores that for the
        // opening line specifically must not reach the screen and truncate
        // with an ellipsis mid-run.
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"one two three four five six seven eight nine ten eleven twelve thirteen",
             "rules":[]}
            """)
        }
    }

    @Test func rejectsImmediateUrgencyOnANonZoneTrigger() {
        // Only drift warnings earn the right to interrupt a hard interval.
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"halfway"},
             "message":"Halfway there.","urgency":"immediate","repeats":false}]}
            """)
        }
    }

    @Test func rejectsAnUnknownTriggerKind() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"moonPhase"},
             "message":"Full moon.","urgency":"atNextBreak","repeats":false}]}
            """)
        }
    }

    @Test func decodesEveryTriggerKind() throws {
        let brief = try decode("""
        {"opening":"Go","rules":[
          {"trigger":{"kind":"zoneBelow","zone":"Z1","sustainedSec":60},"message":"Pick it up.","urgency":"immediate","repeats":true},
          {"trigger":{"kind":"splitCompleted"},"message":"Another one down.","urgency":"atNextBreak","repeats":true},
          {"trigger":{"kind":"splitCompleted","index":3},"message":"Three done.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"distanceReached","km":5},"message":"Five kilometres.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"elapsedReached","minutes":20},"message":"Twenty minutes in.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"phaseStarted","phase":"walk"},"message":"Walk break.","urgency":"atNextBreak","repeats":true},
          {"trigger":{"kind":"halfway"},"message":"Halfway.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"finalKilometre"},"message":"Last one.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"paceFading","percentSlower":12,"sustainedSec":45},"message":"Legs are heavy. Hold on.","urgency":"immediate","repeats":true}
        ]}
        """)
        #expect(brief.rules.count == 9)
        #expect(brief.rules[1].trigger == .splitCompleted(index: nil))
        #expect(brief.rules[2].trigger == .splitCompleted(index: 3))
        #expect(brief.rules[5].trigger == .phaseStarted(.walk))
        #expect(brief.rules[8].trigger == .paceFading(percentSlower: 12, sustainedSec: 45))
    }

    @Test func paceFadingRoundTripsThroughCodable() throws {
        let original = CueTrigger.paceFading(percentSlower: 12, sustainedSec: 45)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CueTrigger.self, from: data)
        #expect(decoded == original)
    }

    @Test func paceFadingDefaultsItsSustainedSecondsWhenOmitted() throws {
        let brief = try decode("""
        {"opening":"Go","rules":[{"trigger":{"kind":"paceFading","percentSlower":15},
         "message":"Hold your form together.","urgency":"atNextBreak","repeats":false}]}
        """)
        #expect(brief.rules[0].trigger == .paceFading(percentSlower: 15, sustainedSec: 45))
    }

    @Test func mayBeImmediateAllowsPaceFadingButRejectsAMilestoneTrigger() {
        // Encouragement half a lap late is not encouragement — but a
        // non-zone, non-pace trigger still has no business interrupting.
        #expect(CueTrigger.paceFading(percentSlower: 12, sustainedSec: 45).mayBeImmediate)
        #expect(!CueTrigger.halfway.mayBeImmediate)
    }
}

struct DefaultCueBundleTests {
    @Test func buildsTheSevenSpecifiedRules() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        #expect(brief.rules.count == 7)
        #expect(brief.opening.isEmpty == false)
    }

    @Test func theDriftAndFadeWarningsAreTheOnlyImmediateOnes() {
        // Struggle coverage must survive offline: the fade rule earns
        // `.immediate` for the same reason the drift warning does.
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        let immediate = brief.rules.filter { $0.urgency == .immediate }
        #expect(immediate.count == 2)
        #expect(immediate.contains { $0.trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30) })
        #expect(immediate.contains { $0.trigger == .paceFading(percentSlower: 12, sustainedSec: 45) })
    }

    @Test func theCeilingFollowsTheSessionsTargetZone() {
        // A tempo day's ceiling is Z3, not Z2 — warning an athlete off Z3
        // during a tempo session would be telling them not to do the workout.
        let brief = defaultBrief(targetZone: "Z3", sessionTitle: "Tempo")
        #expect(brief.rules.contains { $0.trigger == .zoneAbove(ceiling: "Z3", sustainedSec: 30) })
    }

    @Test func everyMessageIsWithinTheWordLimit() {
        for zone in ["Z1", "Z2", "Z3", "Z4"] {
            for rule in defaultBrief(targetZone: zone, sessionTitle: "Run").rules {
                #expect(rule.message.split(whereSeparator: \.isWhitespace).count <= CueRule.maxWords)
            }
        }
    }

    @Test func theSeventhRuleIsTheFadeWarningAndWithinTheWordLimit() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        let fade = brief.rules.last
        #expect(fade?.trigger == .paceFading(percentSlower: 12, sustainedSec: 45))
        #expect((fade?.message.split(whereSeparator: \.isWhitespace).count ?? .max) <= CueRule.maxWords)
        #expect(fade?.repeats == true)
    }

    @Test func milestoneRulesFireOnlyOnce() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        let halfway = brief.rules.first { $0.trigger == .halfway }
        let final = brief.rules.first { $0.trigger == .finalKilometre }
        #expect(halfway?.repeats == false)
        #expect(final?.repeats == false)
    }

    @Test func aPlanDayWithNoZoneFallsBackToZ2() throws {
        let plan = try PlanStore.loadBundled()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // 2026-08-03 is a rest day: no zone in the JSON.
        let restDay = plan.day(on: formatter.date(from: "2026-08-03")!)
        let brief = defaultBrief(for: restDay)
        #expect(brief.rules.contains { $0.trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30) })
    }
}
