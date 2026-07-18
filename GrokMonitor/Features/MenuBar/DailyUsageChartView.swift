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

            if week.isEstimated || !week.hasDailyData {
                Text("Daily bars only show changes between samples. Week-to-date totals are above.")
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

                let fillHeight = trackHeight * CGFloat(Self.fillFraction(forDayUsage: day.totalPercent))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(day.isToday ? Color.accentColor : Color.accentColor.opacity(0.6))
                    .frame(width: barWidth, height: fillHeight)
            }
            .frame(width: barWidth, height: trackHeight, alignment: .bottom)

            Text(day.isAfterReset ? "\(day.weekdaySymbol)*" : day.weekdaySymbol)
                .font(.system(size: 10))
                .foregroundStyle(day.isToday ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
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

}

#if DEBUG
#Preview {
    DailyUsageChartView(week: DailyUsageBuilder.preview())
        .padding()
        .frame(width: 340)
}
#endif
