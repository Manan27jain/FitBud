import SwiftUI

/// A stacked horizontal bar of time spent per zone, for the post-run summary,
/// where it answers "did I actually keep it easy?"
///
/// Not shared with the live Zones page, despite what this comment used to
/// claim. That page draws a zone *ladder*: five fixed rungs with the occupied
/// one lit and widened, answering "where am I right now". This bar's segments
/// are sized by accumulated time and answer "where did the whole run go".
/// Same palette, different questions — merging them would cost both.
struct ZoneBreakdownBar: View {
    let timeInZone: [String: TimeInterval]
    var height: CGFloat = 8

    private var shares: [ZoneShare] { zoneShares(timeInZone: timeInZone) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(shares, id: \.zone.id) { share in
                    Rectangle()
                        .fill(share.zone.color)
                        .frame(width: max(1, geometry.size.width * share.fraction))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay {
            if shares.isEmpty {
                Capsule().fill(.white.opacity(0.12))
            }
        }
    }
}
