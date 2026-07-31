import SwiftUI

/// Zone colours live here rather than on `HRZone` because `HRZone` is held by
/// `WorkoutState`, which is held by `WorkoutEngine` — and the engine must stay
/// Foundation-only to remain testable without a UI.
extension HRZone {
    var color: Color {
        switch id {
        case "Z1": Color(red: 0.196, green: 0.678, blue: 0.902)  // #32ADE6 teal
        case "Z2": Color(red: 0.188, green: 0.820, blue: 0.345)  // #30D158 green
        case "Z3": Color(red: 0.776, green: 0.957, blue: 0.196)  // #C6F432 chartreuse
        case "Z4": Color(red: 1.000, green: 0.624, blue: 0.039)  // #FF9F0A orange
        case "Z5": Color(red: 1.000, green: 0.216, blue: 0.373)  // #FF375F red
        default: .gray
        }
    }
}

enum Theme {
    /// Apple uses yellow rather than white for elapsed time in the Workout app,
    /// which keeps the clock distinct from the metrics without adding chrome.
    static let elapsedYellow = Color(red: 1.0, green: 0.839, blue: 0.039) // #FFD60A

    /// Inactive zone segments. Dark enough to recede, bright enough to still
    /// read as a scale when the display is dimmed in always-on mode.
    static let inactiveZoneOpacity: Double = 0.22

    static let ringWidth: CGFloat = 14
    static let scaleWidth: CGFloat = 5
    /// Gap between the draining phase ring and the zone scale outside it.
    static let ringToScaleGap: CGFloat = 4
}
