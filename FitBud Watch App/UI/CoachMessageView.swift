import SwiftUI

/// A coaching line, over the ring.
///
/// Covering the ring is safe rather than a compromise: `EffortPage` sets a
/// `.containerBackground` wash that tracks the live zone, so green behind the
/// words still means green. The safety signal survives the message sitting on
/// top of it.
///
/// It could not live *inside* the ring in any case — the clear chord at the
/// label's height is about 82pt, which "WARMING UP" barely fits. There is no
/// room for a sentence.
struct CoachMessageView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dims the ring rather than hiding it: the zone wash still reads
            // through, and the text has something to sit on.
            Color.black.opacity(0.55)

            Text(message)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                // 12 words fits three lines at 20pt on a 46mm screen. The scale
                // factor is a guard for an over-length line, so it shrinks
                // rather than truncating mid-sentence.
                .minimumScaleFactor(0.7)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
        }
        .ignoresSafeArea()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onTapGesture(perform: onDismiss)
    }
}
