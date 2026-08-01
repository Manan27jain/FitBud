import Foundation
import Observation

/// User-facing coaching preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class CoachSettings {
    private enum Keys {
        static let speech = "coach.speechEnabled"
        static let provider = "coach.providerID"
    }

    /// Defaults on: the athlete usually runs with AirPods, and the speaker
    /// stays silent by itself when nothing is paired.
    var isSpeechEnabled: Bool {
        didSet { UserDefaults.standard.set(isSpeechEnabled, forKey: Keys.speech) }
    }

    var providerID: ProviderID {
        didSet { UserDefaults.standard.set(providerID.rawValue, forKey: Keys.provider) }
    }

    init() {
        let defaults = UserDefaults.standard
        isSpeechEnabled = defaults.object(forKey: Keys.speech) as? Bool ?? true
        providerID = (defaults.string(forKey: Keys.provider).flatMap(ProviderID.init(rawValue:))) ?? .openAI
    }

    /// The provider to use, or `nil` when no key is configured — in which case
    /// the app is the tracker it already was.
    func makeProvider() -> (any AIProviding)? {
        switch providerID {
        case .openAI:
            guard let key = Secrets.openAIKey else { return nil }
            return OpenAIProvider(apiKey: key)
        case .gemini:
            // Gemini sits behind the same seam and needs no change above it.
            // Implemented after OpenAI is proven on a real run.
            return nil
        }
    }
}
