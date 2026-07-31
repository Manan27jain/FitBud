import SwiftUI

struct HistoryProbeView: View {
    @State private var results: [HealthHistoryProbe.ProbeResult] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Text("Probing…").foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.metric).font(.footnote).bold()
                    Text("\(result.sampleCount) samples")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let oldest = result.oldestSample {
                        Text("from \(oldest.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let days = result.spanDays {
                        Text("\(days) day span").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
        .task {
            results = await HealthHistoryProbe().probe()
            isLoading = false
        }
    }
}
