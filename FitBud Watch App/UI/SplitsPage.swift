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
                    Text("No splits yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(splits, id: \.index) { split in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(split.index)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(formatPace(split.paceSecPerKm))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            if let bpm = split.heartRateAtSplit {
                                Text("\(Int(bpm))")
                                    .font(.system(size: 12, weight: .medium))
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
        .navigationTitle("Splits")
    }

    private func paceColor(for split: Split) -> Color {
        guard let bpm = split.heartRateAtSplit, let zone = HRZone.zone(for: bpm) else {
            return .white.opacity(0.4)
        }
        return zone.color
    }
}
