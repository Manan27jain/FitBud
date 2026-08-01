import SwiftUI

/// Page 4. One row per completed kilometre, with a bar scaled to relative pace
/// so a fast or slow kilometre is visible without comparing numbers.
///
/// This is the only page allowed to scroll: split rows are unbounded, and a
/// scrolling child elsewhere would compete with the crown for paging.
struct SplitsPage: View {
    let model: WorkoutSessionModel

    private var splits: [Split] { model.state.splits }

    /// The slowest split sets the full bar width, so bars compare against the
    /// athlete's own kilometres rather than an arbitrary constant.
    private var slowestPace: Double {
        max(splits.map(\.paceSecPerKm).max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if splits.isEmpty {
                    // Spec §5 is left-aligned throughout. With nothing else
                    // on the page to give the VStack its width, this row used
                    // to centre itself and read as a different layout from the
                    // other four pages.
                    CaptionLabel("NO SPLITS YET")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(splits, id: \.index) { split in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            // Number-led like every other surface: the pace
                            // leads, and the kilometre it belongs to and the
                            // heart rate it was run at are caption tokens
                            // beside it.
                            Text(formatPace(split.paceSecPerKm))
                                .font(.system(size: 20, weight: .bold))
                                .monospacedDigit()
                            CaptionLabel("KM \(split.index)")
                            Spacer(minLength: 0)
                            if let bpm = split.heartRateAtSplit {
                                Text("\(Int(bpm))♥")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(paceColor(for: split))
                                .frame(width: geometry.size.width * (split.paceSecPerKm / slowestPace))
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .containerBackground(Theme.pageWash(Theme.splitsTint), for: .tabView)
        .navigationTitle("Splits")
    }

    private func paceColor(for split: Split) -> Color {
        guard let bpm = split.heartRateAtSplit, let zone = HRZone.zone(for: bpm) else {
            return .white.opacity(0.4)
        }
        return zone.color
    }
}
