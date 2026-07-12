import SwiftUI

/// Settings → Usage style “Daily use” stacked bar chart.
///
/// Each day’s track represents that day’s equal share of the weekly pool (`100/7`).
/// Fill height = dayUsage / dailyCap (capped at a full track).
struct DailyUsageChartView: View {
    let week: DailyUsageWeek
    var onPreviousWeek: (() -> Void)?
    var onNextWeek: (() -> Void)?
    var canGoNext: Bool = true

    private let trackHeight: CGFloat = 108
    private let barWidth: CGFloat = 30
    /// Equal daily share of the weekly SuperGrok pool.
    static let dailyCapPercent: Double = DailyUsageBuilder.dailyCapPercent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily use")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                weekNavButton(systemName: "chevron.left", action: onPreviousWeek)

                Text(week.rangeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                weekNavButton(
                    systemName: "chevron.right",
                    action: onNextWeek,
                    disabled: !canGoNext
                )
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week.displayDays) { day in
                    dayColumn(day)
                }
            }
            .frame(height: trackHeight + 34)

            if !week.legendProducts.isEmpty {
                legend
            }

            if week.isEstimated || !week.hasDailyData {
                Text("Prior days fill in as usage is sampled across the week.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dayColumn(_ day: DailyUsageDay) -> some View {
        VStack(spacing: 5) {
            Text(day.totalPercent > 0.5 ? "\(Int(day.totalPercent.rounded()))%" : " ")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(height: 12)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: barWidth, height: trackHeight)

                let segments = stackedSegments(for: day)
                let dayTotal = max(day.totalPercent, 0.001)
                let fillHeight = trackHeight * CGFloat(Self.fillFraction(forDayUsage: day.totalPercent))

                VStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segmentColor(segment))
                            .frame(
                                width: barWidth,
                                height: fillHeight * CGFloat(segment.percentOfWeekly / dayTotal)
                            )
                    }
                }
                .frame(width: barWidth, height: fillHeight, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(width: barWidth, height: trackHeight, alignment: .bottom)
            .clipped()

            Text(day.isAfterReset ? "\(day.weekdaySymbol)*" : day.weekdaySymbol)
                .font(.system(size: 10))
                .foregroundStyle(day.isToday ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        let items = week.legendProducts
        return VStack(alignment: .leading, spacing: 6) {
            legendRow(Array(items.prefix(3)))
            if items.count > 3 {
                legendRow(Array(items.dropFirst(3)))
            }
        }
    }

    private func legendRow(_ items: [DailyUsageLegendItem]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ForEach(items) { item in
                legendItem(item)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ item: DailyUsageLegendItem) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Circle()
                .fill(legendColor(for: item))
                .frame(width: 7, height: 7)
            Text(legendLabel(for: item))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Short labels so Chat / Build / API fit without overflowing the panel.
    private func legendLabel(for item: DailyUsageLegendItem) -> String {
        switch item.id.lowercased() {
        case "build": return "Build"
        case "before-reset": return "Before reset"
        default: return item.displayName
        }
    }

    private func weekNavButton(
        systemName: String,
        action: (() -> Void)?,
        disabled: Bool = false
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.secondary)
        .disabled(disabled)
    }

    /// Maps weekly-pool percent into track height using the equal daily cap (`100/7`).
    static func fillFraction(forDayUsage percent: Double) -> Double {
        DailyUsageBuilder.fillFraction(forDayUsage: percent)
    }

    /// Bottom → top stack order matching grok.com Usage. Skip zero-height slices.
    private func stackedSegments(for day: DailyUsageDay) -> [DailyUsageSegment] {
        let order = ["before-reset", "api", "build", "chat", "imagine", "voice"]
        return day.segments
            .filter { $0.percentOfWeekly > 0.05 }
            .sorted { a, b in
                let aKey = a.isBeforeReset ? "before-reset" : a.productID.lowercased()
                let bKey = b.isBeforeReset ? "before-reset" : b.productID.lowercased()
                let ai = order.firstIndex(of: aKey) ?? 99
                let bi = order.firstIndex(of: bKey) ?? 99
                return ai < bi
            }
    }

    private func segmentColor(_ segment: DailyUsageSegment) -> Color {
        if segment.isBeforeReset {
            return Color(red: 0.92, green: 0.72, blue: 0.20)
        }
        return Color.product(segment.colorToken)
    }

    private func legendColor(for item: DailyUsageLegendItem) -> Color {
        if item.id == "before-reset" {
            return Color(red: 0.92, green: 0.72, blue: 0.20)
        }
        return Color.product(item.colorToken)
    }
}

#if DEBUG
#Preview {
    DailyUsageChartView(week: DailyUsageBuilder.preview())
        .padding()
        .frame(width: 340)
}
#endif
