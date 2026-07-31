import Foundation

/// Pure geometry for the effort ring.
///
/// Angles are degrees in SwiftUI's convention: 0° is 3 o'clock and angles
/// increase clockwise. Kept separate from `EffortRingView` so the arithmetic
/// can be tested without rendering — which is where the bugs would be.
enum EffortRingGeometry {
    /// The arc sweeps 240°, leaving a 120° gap centred on the bottom of the
    /// screen for the phase countdown. A tachometer, not a closed ring.
    static let startAngle: Double = 150
    static let sweep: Double = 240
    static var endAngle: Double { startAngle + sweep }

    /// Where a heart rate sits on the zone scale.
    ///
    /// Clamps rather than wrapping: a heart rate below Z1 pins to the start and
    /// one above Z5 pins to the end, so the needle can never stray into the
    /// bottom gap where it would imply an effort the athlete isn't at.
    static func angle(forHeartRate bpm: Double) -> Double {
        let lo = Double(HRZone.lowerBound)
        let hi = Double(HRZone.upperBound)
        let clamped = min(max(bpm, lo), hi)
        return startAngle + ((clamped - lo) / (hi - lo)) * sweep
    }

    /// The arc a zone occupies, proportional to its width in beats per minute
    /// rather than an equal fifth — so the scale tells the truth about
    /// physiology instead of flattering the layout.
    static func arc(for zone: HRZone) -> (start: Double, end: Double) {
        (angle(forHeartRate: Double(zone.lowerBPM)),
         angle(forHeartRate: Double(zone.upperBPM)))
    }
}
