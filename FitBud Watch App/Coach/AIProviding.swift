import Foundation

enum ProviderID: String, CaseIterable, Sendable {
    case openAI, gemini

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }
}

enum AIProvidingError: LocalizedError {
    case notConfigured
    case badResponse(Int)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No API key is configured."
        case let .badResponse(code): "The coach service returned \(code)."
        case let .undecodable(detail): "The coach's reply couldn't be read: \(detail)"
        }
    }
}

/// The seam every AI call goes through.
///
/// Nothing above this protocol knows which provider is in use, and nothing
/// below it touches the workout. Every method may fail; every caller has a
/// fallback that keeps the run recording.
protocol AIProviding: Sendable {
    var id: ProviderID { get }
    func brief(context: CoachContext) async throws -> SessionBrief
    func liveCue(context: LiveCoachContext) async throws -> String
    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis
}
