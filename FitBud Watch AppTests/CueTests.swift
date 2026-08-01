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
          {"trigger":{"kind":"finalKilometre"},"message":"Last one.","urgency":"atNextBreak","repeats":false}
        ]}
        """)
        #expect(brief.rules.count == 8)
        #expect(brief.rules[1].trigger == .splitCompleted(index: nil))
        #expect(brief.rules[2].trigger == .splitCompleted(index: 3))
        #expect(brief.rules[5].trigger == .phaseStarted(.walk))
    }
}
