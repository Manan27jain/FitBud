import Foundation

/// One zone's slice of a workout, ready for a stacked bar.
struct ZoneShare: Equatable, Sendable {
    let zone: HRZone
    let seconds: TimeInterval
    /// Share of the total *recorded* zone time, 0…1.
    let fraction: Double
}

/// Turns accumulated zone times into proportional shares in zone order.
///
/// Zones with no recorded time are omitted so a run spent entirely in Z2 draws
/// one solid bar rather than five, four of them zero-width. Fractions are of
/// recorded zone time, not of elapsed time — intervals with no heart-rate
/// sample belong to no zone and must not silently shrink the bar.
func zoneShares(timeInZone: [String: TimeInterval]) -> [ZoneShare] {
    let total = timeInZone.values.reduce(0, +)
    guard total > 0 else { return [] }
    return HRZone.table.compactMap { zone in
        guard let seconds = timeInZone[zone.id], seconds > 0 else { return nil }
        return ZoneShare(zone: zone, seconds: seconds, fraction: seconds / total)
    }
}

/// Whole-percent labels for `shares`, positionally aligned with it, that sum
/// to exactly 100 (for a non-empty input).
///
/// Rounding each share's fraction independently — `Int((fraction * 100).rounded())`
/// — can miss 100 by a point or two (three zones at exactly a third each round
/// to 33/33/33 = 99). Largest-remainder rounding fixes that: floor every
/// percentage, then hand the leftover points one at a time to the zones whose
/// fractional remainders were closest to rounding up. The summary's whole
/// point is a number the athlete trusts, so its own totals must add up.
func zonePercentages(_ shares: [ZoneShare]) -> [Int] {
    guard !shares.isEmpty else { return [] }
    let scaled = shares.map { $0.fraction * 100 }
    var percentages = scaled.map { Int($0.rounded(.down)) }
    let remainder = 100 - percentages.reduce(0, +)
    let order = scaled.indices.sorted { lhs, rhs in
        (scaled[lhs] - scaled[lhs].rounded(.down)) > (scaled[rhs] - scaled[rhs].rounded(.down))
    }
    for index in order.prefix(remainder) {
        percentages[index] += 1
    }
    return percentages
}
