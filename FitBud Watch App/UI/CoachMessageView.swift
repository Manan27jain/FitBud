import SwiftUI

/// The coach's line, in the band `EffortPage` frees beneath the shrunk ring.
///
/// Spec §E4: the original full-screen, 55%-black overlay covered the dial —
/// safe by the "the zone wash still reads through" argument, but the
/// product owner rejected it outright on sight, having seen it. `EffortPage`
/// now shrinks the ring itself to open a band beneath it; this view is just
/// what lives in that band — an eyebrow and the line, no card, no dimming,
/// no background. Type on the wash is the whole design language here.
struct CoachMessageView: View {
    let message: String
    /// The live zone's tint, or its warming-up/no-signal fallback — the same
    /// three-way choice `EffortPage.washTint` makes for the page background,
    /// so the eyebrow always agrees with the wash it sits on.
    let tint: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text("COACH")
                .font(Theme.captionFont)
                .foregroundStyle(tint)

            Text(message)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                // `CueRule`/`SessionBrief` decoding (`Cue.swift`) already
                // rejects anything over twelve words, which is what fits
                // three lines at this size on a 46mm screen. The scale
                // factor is a guard for an over-length line regardless, so
                // it shrinks rather than truncating mid-word.
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        // The `VStack` above has no background, so without this the tap
        // target is only the glyphs themselves — the gaps between the
        // eyebrow and the message, and any slack from `minimumScaleFactor`,
        // would not dismiss. "Tap anywhere on the message" means the whole
        // block.
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
