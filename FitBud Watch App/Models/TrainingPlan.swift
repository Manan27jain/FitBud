import Foundation

/// One work or recovery period inside a repeat block, as written in the plan JSON.
struct PlanInterval: Decodable, Equatable, Sendable {
    let minutes: Double
    let zone: String
    let label: String

    private enum CodingKeys: String, CodingKey {
        case minutes = "min", zone, label
    }
}

/// A structured piece of a session. Mirrors the tagged objects in the JSON's
/// `segments` array.
enum PlanSegment: Equatable, Sendable {
    case warmup(minutes: Double, zone: String, label: String)
    case cooldown(minutes: Double, zone: String, label: String)
    case repeatBlock(times: Int, work: PlanInterval, recover: PlanInterval)
}

extension PlanSegment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, min, zone, label, times, work, recover
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "warmup":
            self = .warmup(
                minutes: try container.decode(Double.self, forKey: .min),
                zone: try container.decode(String.self, forKey: .zone),
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            )
        case "cooldown":
            self = .cooldown(
                minutes: try container.decode(Double.self, forKey: .min),
                zone: try container.decode(String.self, forKey: .zone),
                label: try container.decodeIfPresent(String.self, forKey: .label) ?? ""
            )
        case "repeat":
            self = .repeatBlock(
                times: try container.decode(Int.self, forKey: .times),
                work: try container.decode(PlanInterval.self, forKey: .work),
                recover: try container.decode(PlanInterval.self, forKey: .recover)
            )
        default:
            // Fail loudly rather than silently dropping a session's structure —
            // a segment kind we don't understand means the plan and the app have
            // diverged, which is worth knowing about immediately.
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown plan segment kind '\(kind)'"
            )
        }
    }
}

struct PlanRunWalk: Decodable, Equatable, Sendable {
    let runMin: Double
    let walkMin: Double
}

/// One day of the plan.
struct PlanDay: Decodable, Equatable, Sendable {
    /// `yyyy-MM-dd`, a local calendar day.
    let date: String
    let dow: String
    /// `rest`, `easy`, `long`, `tempo`, `intervals`, `strength`, `cross`, `race`.
    let type: String
    let title: String
    let targetKm: Double
    let targetMin: Double
    let zone: String?
    let segments: [PlanSegment]
    let runWalk: PlanRunWalk?
    let notes: String

    /// Whether this day is something the workout recorder can run. Strength and
    /// cross-training are in the plan but are not tracked by this app, and rest
    /// days are emphatically not sessions.
    var isRunningSession: Bool {
        ["easy", "long", "tempo", "intervals", "race"].contains(type)
    }
}

struct PlanWeek: Decodable, Equatable, Sendable {
    let index: Int
    let start: String
    let end: String
    let focus: String
    let targetKm: Double
    let days: [PlanDay]
}

/// The training plan, decoded from the bundled JSON.
struct TrainingPlan: Decodable, Equatable, Sendable {
    struct Goal: Decodable, Equatable, Sendable {
        let event: String
        /// `yyyy-MM-dd`.
        let date: String
        let distanceKm: Double
        let strategy: String
    }

    let planId: String
    let goal: Goal
    /// Decoded as non-optional on purpose: a plan without its rules block is a
    /// plan whose safety limits are unknown, and this project prefers to fail
    /// loudly at decode time over running with silent defaults — the same
    /// choice `PlanSegment` makes for an unknown segment kind.
    let rules: PlanRules
    let weeks: [PlanWeek]
}

extension TrainingPlan {
    /// Formats a `Date` the way the plan writes days, so lookups are string
    /// comparisons. Comparing `Date`s directly would drag in timezone and
    /// DST questions that a plain calendar day does not have.
    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func day(on date: Date) -> PlanDay? {
        let key = Self.dayKey(for: date)
        for week in weeks {
            if let day = week.days.first(where: { $0.date == key }) { return day }
        }
        return nil
    }

    func week(containing date: Date) -> PlanWeek? {
        let key = Self.dayKey(for: date)
        return weeks.first { week in week.days.contains { $0.date == key } }
    }

    /// Whole days from `date` to race day. Negative once the race has passed.
    func daysToRace(from date: Date) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let raceDay = formatter.date(from: goal.date),
              let today = formatter.date(from: Self.dayKey(for: date)) else { return 0 }
        return Calendar.current.dateComponents([.day], from: today, to: raceDay).day ?? 0
    }

    /// The block's first calendar day, for bounding history queries.
    ///
    /// Builds its own formatter rather than sharing a static one: `DateFormatter`
    /// is a non-`Sendable` class, and the two methods above already take this
    /// approach for the same reason.
    var startDate: Date? {
        guard let first = weeks.first?.start else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: first)
    }
}
