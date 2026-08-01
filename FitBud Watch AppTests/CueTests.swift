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
