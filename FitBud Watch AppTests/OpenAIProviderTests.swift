import Foundation
import Testing
@testable import FitBud_Watch_App

struct OpenAIResponseDecodingTests {
    @Test func extractsTheAssistantMessageContent() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"Nice and easy today."}}]}
        """
        let text = try OpenAIProvider.extractContent(from: Data(json.utf8))
        #expect(text == "Nice and easy today.")
    }

    @Test func throwsWhenThereAreNoChoices() {
        #expect(throws: (any Error).self) {
            try OpenAIProvider.extractContent(from: Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test func decodesABriefFromTheAssistantContent() throws {
        // The model returns the brief as a JSON *string* inside the message,
        // so this is a two-stage decode and each stage can fail separately.
        let inner = #"{\"opening\":\"Easy today.\",\"rules\":[{\"trigger\":{\"kind\":\"halfway\"},\"message\":\"Halfway there.\",\"urgency\":\"atNextBreak\",\"repeats\":false}]}"#
        let json = "{\"choices\":[{\"message\":{\"content\":\"\(inner)\"}}]}"
        let brief = try OpenAIProvider.decodeBrief(from: Data(json.utf8))
        #expect(brief.opening == "Easy today.")
        #expect(brief.rules.count == 1)
    }

    @Test func aBriefWithAnOverlongMessageIsRejectedWholesale() {
        // Never partially applied: a half-valid bundle would coach
        // inconsistently, which is worse than falling back to the default.
        let inner = #"{\"opening\":\"Go\",\"rules\":[{\"trigger\":{\"kind\":\"halfway\"},\"message\":\"one two three four five six seven eight nine ten eleven twelve thirteen\",\"urgency\":\"atNextBreak\",\"repeats\":false}]}"#
        let json = "{\"choices\":[{\"message\":{\"content\":\"\(inner)\"}}]}"
        #expect(throws: (any Error).self) {
            try OpenAIProvider.decodeBrief(from: Data(json.utf8))
        }
    }

    @Test func theModelIdentifierIsASingleConstant() {
        #expect(OpenAIProvider.model == "gpt-5-mini")
    }
}
