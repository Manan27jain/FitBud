import Foundation

/// A heart-rate training zone.
///
/// Deliberately free of any `SwiftUI` dependency: `WorkoutState` holds a zone
/// and `WorkoutEngine` holds a `WorkoutState`, and the engine is required to
/// stay Foundation-only so it remains testable without a UI. Zone colours live
/// in `UI/Theme.swift`.
struct HRZone: Identifiable, Equatable, Sendable {
    /// `"Z1"` … `"Z5"`. Matches the zone ids used in the plan JSON, so Stage 2
    /// can load this table from the plan instead of hardcoding it.
    let id: String
    let name: String
    let lowerBPM: Int
    let upperBPM: Int

    /// Half-open: the lower bound belongs to this zone, the upper bound belongs
    /// to the next one. Without that rule 148 would be in both Z1 and Z2.
    func contains(_ bpm: Double) -> Bool {
        bpm >= Double(lowerBPM) && bpm < Double(upperBPM)
    }
}

extension HRZone {
    /// Karvonen zones for this athlete: max heart rate 207 (observed in the
    /// Health export, not age-estimated) and resting 60.
    static let table: [HRZone] = [
        HRZone(id: "Z1", name: "Recovery",  lowerBPM: 133, upperBPM: 148),
        HRZone(id: "Z2", name: "Easy",      lowerBPM: 148, upperBPM: 163),
        HRZone(id: "Z3", name: "Steady",    lowerBPM: 163, upperBPM: 177),
        HRZone(id: "Z4", name: "Threshold", lowerBPM: 177, upperBPM: 192),
        HRZone(id: "Z5", name: "VO2max",    lowerBPM: 192, upperBPM: 207)
    ]

    static var lowerBound: Int { table[0].lowerBPM }
    static var upperBound: Int { table[table.count - 1].upperBPM }

    /// The zone a heart rate falls in, or `nil` below the first zone.
    ///
    /// At or above the top of Z5 the answer saturates to Z5 rather than going
    /// nil — a heart rate of 210 is emphatically still in the top zone.
    static func zone(for bpm: Double) -> HRZone? {
        if bpm >= Double(upperBound) { return table.last }
        return table.first { $0.contains(bpm) }
    }
}
