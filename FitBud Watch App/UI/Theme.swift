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

    /// The one caption token, for every unit and label that sits to the right
    /// of a number.
    ///
    /// Spec §5 asks for uppercase `.caption2` secondary labels stacked to the
    /// right of their value, Apple's `137BPM AVERAGE HR` grammar, where the
    /// unit and the label are one voice and only the number leads. Five
    /// adjacent crown pages had drifted to 9, 10, 11, 12 and 13pt, in two
    /// different font designs, none of them `.caption2`. Going through a named
    /// token rather than a literal is what stops that happening again — and
    /// `.caption2` also scales with the athlete's text-size setting, which a
    /// hardcoded 9pt never did.
    static let captionFont = Font.caption2.weight(.semibold)

    /// Vertical nudge between the two lines of a `CaptionLabel`, tightening
    /// them into one block rather than two separate rows of text.
    static let captionLineSpacing: CGFloat = -1

    /// The elapsed clock. The same number was 26pt on the Zones page and 34pt
    /// on the Metrics page — one crown turn apart — so it appeared to resize
    /// as the athlete paged. Unified at the larger of the two, which also
    /// keeps it leading the 28pt metric rows beneath it rather than
    /// competing with them. The ceiling is the Zones page's vertical budget:
    /// its two-line "TIME / IN ZONE" and "AVERAGE / HR" labels have to fit
    /// under the ladder without truncating, and that page cannot scroll
    /// because a scrolling child would fight the crown for paging.
    static let elapsedFont = Font.system(size: 34, weight: .semibold)

    static let ringWidth: CGFloat = 14
    static let scaleWidth: CGFloat = 5
    /// Gap between the draining phase ring and the zone scale outside it.
    static let ringToScaleGap: CGFloat = 4
}

/// The uppercase caption that sits to the right of a number — spec §5's
/// grammar, and the only label style on the live pages.
///
/// Built as an explicit leading-aligned `VStack` rather than one `Text`
/// carrying a `\n`: inside an `HStack` row, a multi-line `Text` sizes itself to
/// its longest line and centres the shorter one within that width, so
/// "AVERAGE / HR" rendered as a centred block on an otherwise strictly
/// left-aligned page. `multilineTextAlignment(.leading)` did not reliably
/// correct it. Two `Text`s in a `VStack` cannot get this wrong.
struct CaptionLabel: View {
    let lines: [String]

    init(_ lines: [String]) { self.lines = lines }
    init(_ line: String) { self.lines = [line] }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.captionLineSpacing) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(Theme.captionFont)
        .foregroundStyle(.secondary)
        // Claim the full height of both lines rather than truncating to one
        // with an ellipsis. Load-bearing on the Zones page, which cannot
        // scroll: a scrolling child there would fight the crown for paging.
        .fixedSize(horizontal: false, vertical: true)
    }
}
