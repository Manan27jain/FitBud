import Foundation

/// Decides which cue to deliver and when.
///
/// Pure and deterministic: every timing decision comes from `state.elapsed`,
/// never from a clock, so a whole run can be replayed in a test in
/// milliseconds. This is the file that decides whether the coach feels like a
/// coach or like a nag, which is why it carries the heaviest test suite in the
/// project.
struct CoachEngine {
    /// Spec section 4.
    ///
    /// This constant also carries spec rule 4, "at most one cue per walk
    /// break" — deliberately, not by accident. `deliverQueued` has no
    /// break-identity bookkeeping of its own (that lives in the caller, e.g.
    /// `WorkoutSessionModel`'s own walk-break counter, which gates a
    /// different concern: one live network call per break). Rule 4 holds
    /// here purely because no walk break in the bundled plan reaches 90s —
    /// every one is 60s (4:1 through week 4, 5:1 from week 5, both 60-second
    /// walks) — so a second delivery inside a single break would need more
    /// time than the break has to give. `CoachEngineTests
    /// .theMinimumGapSubsumesOnePerWalkBreak` pins this against the real
    /// bundled plan. Lowering this constant, or introducing a plan whose walk
    /// breaks reach or exceed it, breaks rule 4 silently unless that
    /// invariant is restored.
    static let minimumGap: TimeInterval = 90
    static let urgentFloor: TimeInterval = 45
    /// A queued cue older than this has missed its moment and is dropped.
    static let staleAfter: TimeInterval = 120

    private let rules: [CueRule]
    private let targetDistanceKm: Double

    private var firedRuleIDs: Set<UUID> = []
    private var queued: [(rule: CueRule, queuedAt: TimeInterval)] = []
    private var lastDeliveredAt: TimeInterval?
    /// Elapsed at which the current zone excursion began, per rule.
    private var driftStartedAt: [UUID: TimeInterval] = [:]

    let opening: String

    init(brief: SessionBrief, targetDistanceKm: Double) {
        self.rules = brief.rules
        self.opening = brief.opening
        self.targetDistanceKm = max(targetDistanceKm, 0.1)
    }

    var pendingCount: Int { queued.count }

    /// Feeds one tick in. Returns a cue only if an urgent one fires now, or a
    /// non-urgent one was already queued and this tick lands inside a walk
    /// break; otherwise non-urgent matches are queued for the next walk break.
    mutating func evaluate(state: WorkoutState, events: [WorkoutEvent]) -> Cue? {
        for rule in rules {
            guard !firedRuleIDs.contains(rule.id) || rule.repeats else { continue }
            guard matches(rule, state: state, events: events) else { continue }

            if rule.urgency == .immediate {
                guard canDeliver(at: state.elapsed, urgent: true) else { continue }
                return deliver(rule, at: state.elapsed)
            } else if !queued.contains(where: { $0.rule.id == rule.id }) {
                queued.append((rule, state.elapsed))
                markFired(rule)
            }
        }
        // Being asked to evaluate a tick that already lands inside a walk
        // break is itself the delivery opportunity — no separate signal is
        // needed to say "the athlete is walking now."
        guard state.runWalkPhase == .walk else { return nil }
        return deliverQueued(at: state.elapsed)
    }

    /// Called when the athlete is in a walk break. Delivers at most one queued
    /// cue, dropping any that have gone stale. The 90s minimum gap between any
    /// two cues is what actually bounds this to roughly one per break — walk
    /// breaks in this app are on that order — so no separate break-identity
    /// bookkeeping is needed here.
    mutating func deliverQueued(at elapsed: TimeInterval) -> Cue? {
        queued.removeAll { elapsed - $0.queuedAt > Self.staleAfter }
        guard canDeliver(at: elapsed, urgent: false) else { return nil }
        guard !queued.isEmpty else { return nil }

        let next = queued.removeFirst()
        return deliver(next.rule, at: elapsed)
    }

    // MARK: Private

    private func canDeliver(at elapsed: TimeInterval, urgent: Bool) -> Bool {
        guard let last = lastDeliveredAt else { return true }
        return elapsed - last >= (urgent ? Self.urgentFloor : Self.minimumGap)
    }

    private mutating func deliver(_ rule: CueRule, at elapsed: TimeInterval) -> Cue {
        lastDeliveredAt = elapsed
        markFired(rule)
        return Cue(id: rule.id, message: rule.message, urgency: rule.urgency, firedAt: elapsed)
    }

    private mutating func markFired(_ rule: CueRule) {
        if !rule.repeats { firedRuleIDs.insert(rule.id) }
    }

    private mutating func matches(_ rule: CueRule, state: WorkoutState, events: [WorkoutEvent]) -> Bool {
        switch rule.trigger {
        case let .zoneAbove(ceiling, sustained):
            // Suppressed while walking: the heart rate is meant to be falling.
            guard state.runWalkPhase != .walk else { driftStartedAt[rule.id] = nil; return false }
            guard let zone = state.currentZone, let ceilingZone = zoneNamed(ceiling),
                  zone.lowerBPM > ceilingZone.lowerBPM
            else { driftStartedAt[rule.id] = nil; return false }
            return sustainedLongEnough(rule.id, since: state.elapsed, needed: sustained)

        case let .zoneBelow(floor, sustained):
            guard state.runWalkPhase != .walk else { driftStartedAt[rule.id] = nil; return false }
            guard let floorZone = zoneNamed(floor) else { return false }
            let below = state.currentZone.map { $0.lowerBPM < floorZone.lowerBPM } ?? (state.heartRate != nil)
            guard below else { driftStartedAt[rule.id] = nil; return false }
            return sustainedLongEnough(rule.id, since: state.elapsed, needed: sustained)

        case let .splitCompleted(index):
            return events.contains { event in
                guard case let .splitCompleted(split) = event else { return false }
                return index == nil || split.index == index
            }

        case let .distanceReached(km):
            return state.distanceKm >= km

        case let .elapsedReached(minutes):
            return state.elapsed >= minutes * 60

        case let .phaseStarted(phase):
            return events.contains { $0 == .phaseChanged(phase) }

        case .halfway:
            return state.distanceKm >= targetDistanceKm / 2

        case .finalKilometre:
            return state.distanceKm >= max(targetDistanceKm - 1, 0)

        case let .paceFading(percentSlower, sustained):
            // Suppressed during a walk break, same reasoning as the zone
            // triggers: pace is meant to fall there. And before 1km, GPS lock
            // is still settling — a "fade" this early is measurement noise,
            // not fatigue.
            guard state.runWalkPhase != .walk, state.distanceKm >= 1 else {
                driftStartedAt[rule.id] = nil
                return false
            }
            guard let recent = state.recentPaceSecPerKm,
                  let average = state.averagePaceSecPerKm, average > 0
            else {
                driftStartedAt[rule.id] = nil
                return false
            }
            // A pace *number* rising means slowing.
            let slowerBy = (recent - average) / average * 100
            guard slowerBy >= percentSlower else {
                driftStartedAt[rule.id] = nil
                return false
            }
            return sustainedLongEnough(rule.id, since: state.elapsed, needed: sustained)
        }
    }

    private func zoneNamed(_ id: String) -> HRZone? {
        HRZone.table.first { $0.id == id }
    }

    private mutating func sustainedLongEnough(
        _ ruleID: UUID, since elapsed: TimeInterval, needed: TimeInterval
    ) -> Bool {
        guard let start = driftStartedAt[ruleID] else {
            driftStartedAt[ruleID] = elapsed
            return needed <= 0
        }
        return elapsed - start >= needed
    }
}
