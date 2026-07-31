import SwiftUI

/// A stacked horizontal bar of time spent per zone. Shared by the Zones page
/// and the post-run summary, where it answers "did I actually keep it easy?"
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
