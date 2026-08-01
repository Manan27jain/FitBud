import Foundation

/// The only file in the app that makes a network request.
struct OpenAIProvider: AIProviding {
    /// One place to change the model. `gpt-5-mini` is fast, cheap, and supports
    /// strict structured output, which is what makes the cue bundle safe to
    /// decode rather than hopeful.
    static let model = "gpt-5-mini"

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    let id: ProviderID = .openAI
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private static let systemPrompt = """
    You are a running coach speaking to one athlete through their Apple Watch mid-run.
    Be specific and warm. Never generic. Use their actual numbers.
    Every message you write is read at running pace: at most 12 words, no punctuation
    beyond a full stop or question mark, no emoji, no exclamation marks.
    The athlete's plan requires 80% of running easy; every run in their history was too hard.
    Your job is to keep them honest about that without nagging.
    """

    func brief(context: CoachContext) async throws -> SessionBrief {
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                Write the coaching for this session: one opening line, and 4 to 7 cue rules.
                Only zoneAbove and zoneBelow rules may have urgency "immediate".
                """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "session_brief", "strict": true, "schema": Self.briefSchema]
            ]
        ]
        let data = try await post(body)
        return try Self.decodeBrief(from: data)
    }

    func liveCue(context: LiveCoachContext) async throws -> String {
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                Say one thing to the athlete right now. At most 12 words. Plain text only.
                """]
            ]
        ]
        let data = try await post(body)
        return try Self.extractContent(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
        let distance = String(format: "%.2f", workout.distanceMeters / 1000)
        let pace = workout.averagePaceSecPerKm.map(formatPace) ?? "unknown"
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                They just finished: \(distance)km in \(formatDuration(workout.duration)), \
                average pace \(pace)/km, average heart rate \
                \(workout.averageHeartRate.map { String(Int($0)) } ?? "unknown")bpm.

                Write a two-sentence summary and one concrete takeaway for next time.
                """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "workout_analysis", "strict": true, "schema": Self.analysisSchema]
            ]
        ]
        let data = try await post(body)
        let content = try Self.extractContent(from: data)
        return try JSONDecoder().decode(WorkoutAnalysis.self, from: Data(content.utf8))
    }

    // MARK: Transport

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Short by design: a coaching line that arrives late is worthless, and
        // the caller always has a bundled cue to fall back on.
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProvidingError.badResponse(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProvidingError.badResponse(http.statusCode)
        }
        return data
    }

    // MARK: Decoding — pure, and unit tested

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    static func extractContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AIProvidingError.undecodable("no choices in response")
        }
        return content
    }

    static func decodeBrief(from data: Data) throws -> SessionBrief {
        let content = try extractContent(from: data)
        do {
            return try JSONDecoder().decode(SessionBrief.self, from: Data(content.utf8))
        } catch {
            // Rejected wholesale rather than partially applied: a half-valid
            // bundle would coach inconsistently, which is worse than the
            // default bundle playing.
            throw AIProvidingError.undecodable(error.localizedDescription)
        }
    }

    // MARK: Schemas

    private static let briefSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["opening", "rules"],
        "properties": [
            "opening": ["type": "string"],
            "rules": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["trigger", "message", "urgency", "repeats"],
                    "properties": [
                        "trigger": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["kind"],
                            "properties": [
                                "kind": ["type": "string", "enum": [
                                    "zoneAbove", "zoneBelow", "splitCompleted", "distanceReached",
                                    "elapsedReached", "phaseStarted", "halfway", "finalKilometre"
                                ]],
                                "zone": ["type": "string"],
                                "sustainedSec": ["type": "number"],
                                "index": ["type": "integer"],
                                "km": ["type": "number"],
                                "minutes": ["type": "number"],
                                "phase": ["type": "string", "enum": ["run", "walk"]]
                            ]
                        ],
                        "message": ["type": "string"],
                        "urgency": ["type": "string", "enum": ["immediate", "atNextBreak"]],
                        "repeats": ["type": "boolean"]
                    ]
                ]
            ]
        ]
    ]

    private static let analysisSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "takeaway"],
        "properties": [
            "summary": ["type": "string"],
            "takeaway": ["type": "string"]
        ]
    ]
}
