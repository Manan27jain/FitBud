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


    // MARK: Page washes (spec §3)

    /// A page's meaning tint, washed from the top down to pure black.
    ///
    /// Deliberately weak. Spec §5 wants left-aligned type on a black
    /// background with the zone scale as the only chrome, and the Series 10
    /// dims rather than sleeps during a workout — so the tint has to survive
    /// being halved without ever eating the contrast of the numerals sitting
    /// on top of it. At 0.28 over black even the brightest zone hue
    /// composites to roughly 5% luminance, which leaves white type at better
    /// than 11:1. A hint that the page has changed, not a flood of colour.
    static func pageWash(_ tint: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(0.28), location: 0),
                .init(color: tint.opacity(0.05), location: 0.45),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Static tints for the four pages whose meaning does not move.
    ///
    /// All four are chosen from *outside* the zone palette on purpose. The
    /// Effort page's wash is the one that carries a reading — it follows the
    /// live zone, so the whole screen warms as the athlete drifts out of Z2 —
    /// and that signal only works if a coloured background nowhere else in
    /// the app can be mistaken for a zone.
    static let controlsTint = Color(white: 0.5)
    static let zonesTint = Color(red: 0.369, green: 0.361, blue: 0.902)   // #5E5CE6 indigo
    /// The page the yellow clock leads, so it is washed in the clock's own
    /// hue. Not a zone colour, and the only warm one of the four.
    ///
    /// Dialled back because yellow is far more luminous than indigo, purple or
    /// grey at the same opacity: at the full 0.28 the wash weighed noticeably
    /// more than the other three pages' and, worse, put the yellow clock on a
    /// yellow ground where it lost its punch. This is a perceptual correction,
    /// not a different design.
    static let metricsTint = elapsedYellow.opacity(0.55)
    static let splitsTint = Color(red: 0.749, green: 0.353, blue: 0.949)  // #BF5AF2 purple
    /// The Effort page with no heart rate at all — no zone to report, so no
    /// colour to report it in.
    static let noSignalTint = Color(white: 0.32)
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

/// The thin capsule bar used wherever the app shows completed-against-planned.
///
/// Lives here beside `CaptionLabel` because it is now used by both the home
/// screen and the plan browser, and two copies of a progress bar drift the way
/// the five live pages' typography drifted before `Theme` existed.
struct ProgressTrack: View {
    let fraction: Double
    var color: Color = .green

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    // A floor of 2pt so a barely-started week still shows a
                    // mark rather than an empty track that reads as "no data".
                    .frame(width: max(2, geometry.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
