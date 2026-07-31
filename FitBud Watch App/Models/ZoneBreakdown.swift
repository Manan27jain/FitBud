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
