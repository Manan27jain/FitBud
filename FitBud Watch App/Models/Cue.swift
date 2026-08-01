import Foundation

enum CueTrigger: Equatable, Sendable {
    case zoneAbove(ceiling: String, sustainedSec: TimeInterval)
    case zoneBelow(floor: String, sustainedSec: TimeInterval)
    /// `nil` index matches any split.
    case splitCompleted(index: Int?)
    case distanceReached(km: Double)
    case elapsedReached(minutes: Double)
    case phaseStarted(RunWalkPhase)
    case halfway
    case finalKilometre
    /// Recent pace slower than the session average by at least
    /// `percentSlower`, sustained for `sustainedSec` — the athlete fading
    /// under fatigue rather than a momentary GPS wobble.
    case paceFading(percentSlower: Double, sustainedSec: TimeInterval)

    /// Only drift warnings — and a struggle fade, which is the same shape of
    /// warning — may interrupt. Everything else waits for a walk break: a
    /// milestone delivered sixty seconds late is still a milestone, but
    /// encouragement delivered half a lap late is not encouragement.
    var mayBeImmediate: Bool {
        switch self {
        case .zoneAbove, .zoneBelow, .paceFading: true
        default: false
        }
    }
}

extension CueTrigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, zone, sustainedSec, index, km, minutes, phase, percentSlower
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "zoneAbove":
            self = .zoneAbove(
                ceiling: try container.decode(String.self, forKey: .zone),
                sustainedSec: try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedSec) ?? 30
            )
        case "zoneBelow":
            self = .zoneBelow(
                floor: try container.decode(String.self, forKey: .zone),
                sustainedSec: try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedSec) ?? 60
            )
        case "splitCompleted":
            self = .splitCompleted(index: try container.decodeIfPresent(Int.self, forKey: .index))
        case "distanceReached":
            self = .distanceReached(km: try container.decode(Double.self, forKey: .km))
        case "elapsedReached":
            self = .elapsedReached(minutes: try container.decode(Double.self, forKey: .minutes))
        case "phaseStarted":
            let phase = try container.decode(String.self, forKey: .phase)
            self = .phaseStarted(phase == "run" ? .run : .walk)
        case "halfway":
            self = .halfway
        case "finalKilometre":
            self = .finalKilometre
        case "paceFading":
            self = .paceFading(
                percentSlower: try container.decode(Double.self, forKey: .percentSlower),
                sustainedSec: try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedSec) ?? 45
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown cue trigger kind '\(kind)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .zoneAbove(zone, seconds):
            try container.encode("zoneAbove", forKey: .kind)
            try container.encode(zone, forKey: .zone)
            try container.encode(seconds, forKey: .sustainedSec)
        case let .zoneBelow(zone, seconds):
            try container.encode("zoneBelow", forKey: .kind)
            try container.encode(zone, forKey: .zone)
            try container.encode(seconds, forKey: .sustainedSec)
        case let .splitCompleted(index):
            try container.encode("splitCompleted", forKey: .kind)
            try container.encodeIfPresent(index, forKey: .index)
        case let .distanceReached(km):
            try container.encode("distanceReached", forKey: .kind)
            try container.encode(km, forKey: .km)
        case let .elapsedReached(minutes):
            try container.encode("elapsedReached", forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        case let .phaseStarted(phase):
            try container.encode("phaseStarted", forKey: .kind)
            try container.encode(phase == .run ? "run" : "walk", forKey: .phase)
        case .halfway:
            try container.encode("halfway", forKey: .kind)
        case .finalKilometre:
            try container.encode("finalKilometre", forKey: .kind)
        case let .paceFading(percentSlower, seconds):
            try container.encode("paceFading", forKey: .kind)
            try container.encode(percentSlower, forKey: .percentSlower)
            try container.encode(seconds, forKey: .sustainedSec)
        }
    }
}

enum CueUrgency: String, Codable, Equatable, Sendable {
    /// Interrupts, even mid-interval. Reserved for drift warnings.
    case immediate
    /// Queues until the next walk break.
    case atNextBreak
}

struct CueRule: Equatable, Sendable, Codable, Identifiable {
    /// Twelve words fits three lines at 20pt on a 46mm screen, and is about as
    /// much as anyone reads at running pace.
    static let maxWords = 12

    let id: UUID
    let trigger: CueTrigger
    let message: String
    let urgency: CueUrgency
    let repeats: Bool

    init(trigger: CueTrigger, message: String, urgency: CueUrgency = .atNextBreak, repeats: Bool = false) {
        self.id = UUID()
        self.trigger = trigger
        self.message = message
        self.urgency = urgency
        self.repeats = repeats
    }

    private enum CodingKeys: String, CodingKey {
        case trigger, message, urgency, repeats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The model does not supply ids; they exist only so the engine can
        // remember which non-repeating rules have already fired.
        id = UUID()
        trigger = try container.decode(CueTrigger.self, forKey: .trigger)
        message = try container.decode(String.self, forKey: .message)
        urgency = try container.decodeIfPresent(CueUrgency.self, forKey: .urgency) ?? .atNextBreak
        repeats = try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? false

        let words = message.split(whereSeparator: \.isWhitespace).count
        guard words <= Self.maxWords else {
            throw DecodingError.dataCorruptedError(
                forKey: .message, in: container,
                debugDescription: "Cue message is \(words) words; the limit is \(Self.maxWords)"
            )
        }
        guard urgency != .immediate || trigger.mayBeImmediate else {
            throw DecodingError.dataCorruptedError(
                forKey: .urgency, in: container,
                debugDescription: "Only zone triggers may be immediate"
            )
        }
    }
}

/// A cue the engine decided to deliver, with the rule it came from.
struct Cue: Equatable, Sendable, Identifiable {
    let id: UUID
    let message: String
    let urgency: CueUrgency
    /// Elapsed seconds into the workout when it fired.
    let firedAt: TimeInterval
}

struct SessionBrief: Equatable, Sendable, Decodable {
    /// Spoken and shown as the run begins.
    let opening: String
    let rules: [CueRule]

    init(opening: String, rules: [CueRule]) {
        self.opening = opening
        self.rules = rules
    }

    private enum CodingKeys: String, CodingKey {
        case opening, rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opening = try container.decode(String.self, forKey: .opening)
        rules = try container.decode([CueRule].self, forKey: .rules)

        // The same guard `CueRule.message` gets, and for the same reason:
        // `CoachMessageView` shrinks an over-length line rather than
        // truncating it, but only up to a point, and twelve words is what
        // actually fits three lines at 20pt on a 46mm screen. Nothing at the
        // schema level bounds `opening` the way `CueRule`'s decoding bounds
        // `message` — the system prompt only *asks* the model to keep every
        // message to twelve words — so an opening this long must be rejected
        // here rather than reach the screen and truncate mid-sentence.
        let words = opening.split(whereSeparator: \.isWhitespace).count
        guard words <= CueRule.maxWords else {
            throw DecodingError.dataCorruptedError(
                forKey: .opening, in: container,
                debugDescription: "Opening line is \(words) words; the limit is \(CueRule.maxWords)"
            )
        }
    }
}

struct WorkoutAnalysis: Equatable, Sendable, Decodable {
    /// One or two sentences on how the run went.
    let summary: String
    /// One concrete thing to carry into the next session.
    let takeaway: String
}
