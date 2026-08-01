import Foundation
import Testing
@testable import FitBud_Watch_App

struct SecretsTests {
    @Test func missingOrEmptyKeysReadAsNil() {
        // No Secrets.plist is bundled in a test run, and an all-empty example
        // must not read as "configured" — otherwise the app would try to
        // authenticate with an empty bearer token and fail confusingly.
        #expect(Secrets.openAIKey == nil)
        #expect(Secrets.geminiKey == nil)
        #expect(Secrets.hasAnyKey == false)
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
