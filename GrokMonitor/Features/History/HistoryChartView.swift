import SwiftUI
import Charts

struct HistoryChartView: View {
    @ObservedObject var history: HistoryStore

    /// Chronological samples; reads `@Published recent` so the chart refreshes live.
    private var snapshots: [WeeklyUsageSnapshot] {
        history.recent.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage History")
                .font(.title2.weight(.semibold))

            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Usage samples appear here after the first successful refresh.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(snapshots) { snap in
                    LineMark(
                        x: .value("Time", snap.fetchedAt),
                        y: .value("Used %", snap.usedPercent)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", snap.fetchedAt),
                        y: .value("Used %", snap.usedPercent)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Used %")
                .frame(minHeight: 220)

                if let latest = snapshots.last {
                    Chart {
                        ForEach(latest.visibleProducts) { product in
                            BarMark(
                                x: .value("Product", product.displayName),
                                y: .value("Percent", product.percentOfPool)
                            )
                            .foregroundStyle(Color.product(product.colorToken))
                        }
                    }
                    .frame(minHeight: 160)
                    .chartYAxisLabel("Share of pool %")
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
        .onDisappear {
            AppDelegate.hideDockIfNoWindows()
        }
    }
}
