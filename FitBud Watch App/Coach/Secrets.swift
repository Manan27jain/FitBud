import Foundation

/// Reads API keys from a gitignored `Secrets.plist` in the app bundle.
///
/// Not an `.xcconfig`, despite that being the obvious choice: this project has no
/// `baseConfigurationReference`, so an xcconfig would never be read, and adding
/// one means editing `project.pbxproj` — which Xcode rewrites cosmetically on
/// most builds, so a hand edit is easy to lose. A plist in `Resources/` is picked
/// up by the synchronized folder group automatically, the same way the training
/// plan JSON already is.
///
/// A key in an app bundle is readable by anyone holding the bundle. For a
/// personal sideloaded app that is an acceptable trade. It would not be for
/// anything distributed.
enum Secrets {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: String]
        else { return [:] }
        return dictionary
    }()

    /// Normalises a raw plist dictionary: absent, empty and whitespace-only
    /// values all read as "not configured", so an unconfigured app disables AI
    /// cleanly instead of sending an empty bearer token.
    static func normalise(_ values: [String: String], key: String) -> String? {
        guard let value = values[key], !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return value
    }

    static var openAIKey: String? { normalise(values, key: "OPENAI_API_KEY") }
    static var geminiKey: String? { normalise(values, key: "GEMINI_API_KEY") }
    static var hasAnyKey: Bool { openAIKey != nil || geminiKey != nil }
}
