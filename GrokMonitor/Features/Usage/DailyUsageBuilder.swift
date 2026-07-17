import Foundation

/// Builds a Settings → Usage style “Daily use” series.
///
/// Priority:
/// 1. Server daily series (when discovered / passed in)
/// 2. Local snapshot deltas between successive sample days **within the billing week**
/// 3. Mid-period reset/rebase (used% drops, `resetsAt` unchanged): drop prior days and
///    start tracking from that day with the current week-to-date total
/// 4. Until two valid sample days exist (normal week), leave bars empty
enum DailyUsageBuilder {

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE"
        return f
    }()
    /// Amber used for "Before reset" segments (matches grok.com Usage UI).
    static let beforeResetColor = ProductColor.voice

    /// Equal daily share of the weekly SuperGrok pool.
    static let dailyCapPercent: Double = 100.0 / 7.0

    /// Maps weekly-pool percent into 0…1 of the daily track (`100/7` cap).
    static func fillFraction(forDayUsage percent: Double) -> Double {
        guard percent > 0.05 else { return 0 }
        return min(percent / dailyCapPercent, 1.0)
    }

    static func week(
        history: [WeeklyUsageSnapshot],
        current: WeeklyUsageSnapshot?,
        serverDaily: [DailyUsageSnapshot] = [],
        weekOffset: Int = 0,
        resetsAt: Date? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DailyUsageWeek {
        var cal = calendar
        cal.firstWeekday = 2 // Monday — chart shows Mon → Sun

        let (weekStart, weekEnd) = billingWeekBounds(
            resetsAt: resetsAt ?? current?.resetsAt,
            weekOffset: weekOffset,
            calendar: cal,
            now: now
        )

        // Prefer server daily series when it covers this week.
        if !serverDaily.isEmpty {
            let weekDays = buildDaysFromServer(
                serverDaily: serverDaily,
                weekStart: weekStart,
                calendar: cal,
                now: now
            )
            if weekDays.contains(where: { !$0.segments.isEmpty }) {
                return finalize(weekStart: weekStart, weekEnd: weekEnd, days: weekDays, isEstimated: false)
            }
        }

        var samples = history
        if let current {
            if samples.isEmpty || (samples.last.map { $0.fetchedAt < current.fetchedAt } ?? true) {
                if let last = samples.last,
                   abs(last.usedPercent - current.usedPercent) < 0.05,
                   abs(last.fetchedAt.timeIntervalSince(current.fetchedAt)) < 60,
                   cal.isDate(last.fetchedAt, inSameDayAs: current.fetchedAt)
                {
                    // same-day near-duplicate — keep history only
                } else {
                    samples.append(current)
                }
            }
        }
        samples.sort { $0.fetchedAt < $1.fetchedAt }

        // End-of-day cumulative used% (last sample that day).
        var endOfDay: [Date: WeeklyUsageSnapshot] = [:]
        for sample in samples {
            let day = cal.startOfDay(for: sample.fetchedAt)
            if let existing = endOfDay[day] {
                if let existingResets = existing.resetsAt,
                   let sampleResets = sample.resetsAt,
                   sampleResets.timeIntervalSince(existingResets) > 12 * 3600 {
                    continue
                }
                if sample.fetchedAt >= existing.fetchedAt {
                    endOfDay[day] = sample
                }
            } else {
                endOfDay[day] = sample
            }
        }

        let sortedDays = endOfDay.keys.sorted()
        var cumulativeByDay: [Date: Double] = [:]
        var productsByDay: [Date: [ProductUsage]] = [:]
        for day in sortedDays {
            guard let snap = endOfDay[day] else { continue }
            cumulativeByDay[day] = snap.usedPercent
            productsByDay[day] = snap.products
        }

        let weekdayFormatter = Self.weekdayFormatter
        weekdayFormatter.calendar = cal

        // Only samples inside this billing week participate in day-over-day math.
        // Prior-period samples must not create false "before reset" bars mid-week.
        let inWeekSampleDays = sortedDays.filter { day in
            day >= weekStart && day <= weekEnd
        }

        // Mid-period server reset/rebase (used% drops, `resetsAt` unchanged): drop every
        // prior sample day and start the daily series from that day forward.
        let trackingStartDay = latestMidPeriodRecalibrationDay(
            sampleDays: inWeekSampleDays,
            cumulativeByDay: cumulativeByDay,
            endOfDay: endOfDay
        )
        let validSampleDays: [Date]
        if let trackingStartDay {
            validSampleDays = inWeekSampleDays.filter { $0 >= trackingStartDay }
        } else {
            validSampleDays = inWeekSampleDays
        }

        var days: [DailyUsageDay] = []

        for offset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let isToday = cal.isDate(dayStart, inSameDayAs: now)
            let symbol = String(weekdayFormatter.string(from: dayStart).prefix(3))

            // Prefer the latest prior *valid* sample day (not only calendar yesterday), so a
            // missing poll day still yields a correct multi-day delta on the next sample.
            let prevDayKey = validSampleDays.last { $0 < dayStart }
            let prevCumulative = prevDayKey.flatMap { cumulativeByDay[$0] }
            let dayCumulative = cumulativeByDay[dayStart]
            // Dropped pre-reset days still have snapshots; never paint them.
            let dayIsValid = validSampleDays.contains(dayStart)
            let isTrackingStart = trackingStartDay.map { cal.isDate(dayStart, inSameDayAs: $0) } ?? false

            var segments: [DailyUsageSegment] = []
            var isAfterReset = isTrackingStart

            if let dayCumulative, dayIsValid {
                let products = productsByDay[dayStart] ?? current?.products ?? []
                let previousProducts = prevDayKey.flatMap { productsByDay[$0] } ?? []
                if let previous = prevCumulative {
                    if dayCumulative + 5 < previous {
                        // Another drop after we already re-started tracking.
                        isAfterReset = true
                        if dayCumulative > 0.05 {
                            segments.append(
                                contentsOf: segmentsFromProducts(
                                    products,
                                    fallbackTotal: dayCumulative
                                )
                            )
                        }
                    } else {
                        segments.append(
                            contentsOf: growthSegments(
                                previousUsed: previous,
                                dayUsed: dayCumulative,
                                previousProducts: previousProducts,
                                products: products
                            )
                        )
                    }
                } else if dayCumulative > 0.05, isTrackingStart {
                    // Fresh start after reset: current week-to-date is today's bar.
                    // Later days use normal day-over-day deltas from here.
                    segments.append(
                        contentsOf: segmentsFromProducts(products, fallbackTotal: dayCumulative)
                    )
                }
                // First sample of a normal week (no reset): leave empty until day two.
            }

            days.append(
                DailyUsageDay(
                    dayStart: dayStart,
                    weekdaySymbol: symbol,
                    segments: segments,
                    isToday: isToday,
                    isAfterReset: isAfterReset
                )
            )
        }

        // Estimated while we only have a single post-reset sample day.
        let isEstimated = validSampleDays.count < 2 && weekOffset == 0
        return finalize(weekStart: weekStart, weekEnd: weekEnd, days: days, isEstimated: isEstimated)
    }

    /// Preview week matching the grok.com Usage reference screenshot.
    static func preview(now: Date = Date(), calendar: Calendar = .current) -> DailyUsageWeek {
        var cal = calendar
        cal.firstWeekday = 2
        let weekStart = startOfWeek(containing: now, calendar: cal)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        let pattern: [(Double, Double, Double)] = [
            (0, 0, 0),   // Mon
            (0, 0, 0),   // Tue
            (7, 2, 1),   // Wed ~10
            (0, 0, 0),   // Thu — before-reset handled below
            (18, 5, 1),  // Fri ~24
            (2, 1, 0),   // Sat ~3
            (0, 0, 0)    // Sun
        ]

        let weekdayFormatter = Self.weekdayFormatter

        var days: [DailyUsageDay] = []
        for offset in 0..<7 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let isToday = cal.isDate(dayStart, inSameDayAs: now)
            var segments: [DailyUsageSegment] = []
            if offset == 3 {
                segments = [
                    DailyUsageSegment(
                        productID: "before-reset",
                        displayName: "Before reset",
                        percentOfWeekly: 8,
                        colorToken: .voice,
                        isBeforeReset: true
                    )
                ]
            } else {
                let (b, a, c) = pattern[offset]
                if b > 0 {
                    segments.append(
                        DailyUsageSegment(
                            productID: "build",
                            displayName: "Grok Build",
                            percentOfWeekly: b,
                            colorToken: .build,
                            isBeforeReset: false
                        )
                    )
                }
                if a > 0 {
                    segments.append(
                        DailyUsageSegment(
                            productID: "api",
                            displayName: "API",
                            percentOfWeekly: a,
                            colorToken: .api,
                            isBeforeReset: false
                        )
                    )
                }
                if c > 0 {
                    segments.append(
                        DailyUsageSegment(
                            productID: "chat",
                            displayName: "Chat",
                            percentOfWeekly: c,
                            colorToken: .chat,
                            isBeforeReset: false
                        )
                    )
                }
            }
            days.append(
                DailyUsageDay(
                    dayStart: dayStart,
                    weekdaySymbol: String(weekdayFormatter.string(from: dayStart).prefix(3)),
                    segments: segments,
                    isToday: isToday,
                    isAfterReset: offset == 3
                )
            )
        }

        return finalize(weekStart: weekStart, weekEnd: weekEnd, days: days, isEstimated: false)
    }

    // MARK: - Billing week

    /// Week ending the day before `resetsAt` (billing period), shifted by `weekOffset`.
    static func billingWeekBounds(
        resetsAt: Date?,
        weekOffset: Int,
        calendar: Calendar,
        now: Date
    ) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = 2

        let weekEnd: Date
        if let resetsAt {
            let resetDay = cal.startOfDay(for: resetsAt)
            weekEnd = cal.date(byAdding: .day, value: -1, to: resetDay) ?? resetDay
        } else {
            let weekStart = startOfWeek(containing: now, calendar: cal)
            weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        }

        let shiftedEnd = cal.date(byAdding: .day, value: weekOffset * 7, to: weekEnd) ?? weekEnd
        let shiftedStart = cal.date(byAdding: .day, value: -6, to: shiftedEnd) ?? shiftedEnd
        return (shiftedStart, shiftedEnd)
    }

    // MARK: - Helpers

    private static func buildDaysFromServer(
        serverDaily: [DailyUsageSnapshot],
        weekStart: Date,
        calendar: Calendar,
        now: Date
    ) -> [DailyUsageDay] {
        let weekdayFormatter = Self.weekdayFormatter
        weekdayFormatter.calendar = calendar

        let byDay = Dictionary(
            serverDaily.map { (calendar.startOfDay(for: $0.dayStart), $0) },
            uniquingKeysWith: { _, last in last }
        )

        var days: [DailyUsageDay] = []
        for offset in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let symbol = String(weekdayFormatter.string(from: dayStart).prefix(3))
            let snap = byDay[dayStart]
            let segments: [DailyUsageSegment]
            if let snap, snap.percentOfWeekly > 0.05 {
                segments = segmentsFromProducts(snap.products, fallbackTotal: snap.percentOfWeekly)
            } else {
                segments = []
            }
            days.append(
                DailyUsageDay(
                    dayStart: dayStart,
                    weekdaySymbol: symbol,
                    segments: segments,
                    isToday: calendar.isDate(dayStart, inSameDayAs: now),
                    isAfterReset: false
                )
            )
        }
        return days
    }

    private static func finalize(
        weekStart: Date,
        weekEnd: Date,
        days: [DailyUsageDay],
        isEstimated: Bool
    ) -> DailyUsageWeek {
        var legend: [DailyUsageLegendItem] = []
        var seen = Set<String>()
        var showsBeforeReset = false
        for day in days {
            for seg in day.segments {
                if seg.isBeforeReset { showsBeforeReset = true }
                let key = seg.isBeforeReset ? "before-reset" : seg.productID
                guard seen.insert(key).inserted else { continue }
                legend.append(
                    DailyUsageLegendItem(
                        id: key,
                        displayName: seg.displayName,
                        colorToken: seg.colorToken
                    )
                )
            }
        }
        legend.sort { a, b in
            let order = ["chat", "build", "voice", "api", "imagine", "before-reset"]
            let ai = order.firstIndex(of: a.id) ?? 99
            let bi = order.firstIndex(of: b.id) ?? 99
            return ai < bi
        }

        let hasDailyData = days.contains { !$0.segments.isEmpty }
        return DailyUsageWeek(
            weekStart: weekStart,
            weekEnd: weekEnd,
            days: days,
            legendProducts: legend,
            showsBeforeReset: showsBeforeReset,
            hasDailyData: hasDailyData,
            isEstimated: isEstimated
        )
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysFromStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromStart, to: day) ?? day
    }

    /// Absolute product slices — only products with usage above zero.
    private static func segmentsFromProducts(
        _ products: [ProductUsage],
        fallbackTotal: Double? = nil
    ) -> [DailyUsageSegment] {
        let visible = products.filter { $0.percentOfPool > 0.05 }
        if !visible.isEmpty {
            return ProductCatalog.sortForDisplay(visible).map { product in
                DailyUsageSegment(
                    productID: product.id,
                    displayName: product.displayName,
                    percentOfWeekly: product.percentOfPool,
                    colorToken: product.colorToken,
                    isBeforeReset: false
                )
            }
        }
        guard let total = fallbackTotal, total > 0.05 else { return [] }
        return [
            DailyUsageSegment(
                productID: "other",
                displayName: "Other",
                percentOfWeekly: total,
                colorToken: .other,
                isBeforeReset: false
            )
        ]
    }

    /// True when `resetsAt` moved forward enough to indicate a SuperGrok period rollover.
    /// Missing metadata falls back to treating a large used% drop as a rollover (legacy heuristic).
    private static func isBillingPeriodAdvanced(from previous: Date?, to current: Date?) -> Bool {
        guard let previous, let current else { return true }
        return current.timeIntervalSince(previous) > 12 * 3600
    }

    /// Latest day whose cumulative used% fell sharply without `resetsAt` advancing (server rebase).
    private static func latestMidPeriodRecalibrationDay(
        sampleDays: [Date],
        cumulativeByDay: [Date: Double],
        endOfDay: [Date: WeeklyUsageSnapshot]
    ) -> Date? {
        guard sampleDays.count >= 2 else { return nil }
        var latest: Date?
        for index in 1..<sampleDays.count {
            let previousDay = sampleDays[index - 1]
            let day = sampleDays[index]
            guard
                let previousUsed = cumulativeByDay[previousDay],
                let dayUsed = cumulativeByDay[day],
                dayUsed + 5 < previousUsed
            else { continue }
            let previousResets = endOfDay[previousDay]?.resetsAt
            let dayResets = endOfDay[day]?.resetsAt
            if isBillingPeriodAdvanced(from: previousResets, to: dayResets) {
                continue
            }
            latest = day
        }
        return latest
    }

    /// Day-over-day growth: prefer per-product increases; fall back to total delta weighted by mix.
    private static func growthSegments(
        previousUsed: Double,
        dayUsed: Double,
        previousProducts: [ProductUsage],
        products: [ProductUsage]
    ) -> [DailyUsageSegment] {
        let productSegments = productDeltaSegments(from: previousProducts, to: products)
        let productSum = productSegments.reduce(0.0) { $0 + $1.percentOfWeekly }
        let totalDelta = max(0, dayUsed - previousUsed)
        if !productSegments.isEmpty, productSum > 0.05 {
            return productSegments
        }
        if totalDelta > 0.05 {
            return distribute(total: totalDelta, products: products)
        }
        return []
    }

    /// Day-over-day growth per product — omits products that did not increase.
    private static func productDeltaSegments(
        from previous: [ProductUsage],
        to current: [ProductUsage]
    ) -> [DailyUsageSegment] {
        var previousByID: [String: Double] = [:]
        for product in previous {
            previousByID[product.id.lowercased()] = product.percentOfPool
        }

        var deltas: [ProductUsage] = []
        for product in current {
            let key = product.id.lowercased()
            let delta = max(0, product.percentOfPool - (previousByID[key] ?? 0))
            guard delta > 0.05 else { continue }
            deltas.append(
                ProductUsage(
                    id: product.id,
                    displayName: product.displayName,
                    percentOfPool: delta,
                    colorToken: product.colorToken
                )
            )
        }
        return ProductCatalog.sortForDisplay(deltas).map { product in
            DailyUsageSegment(
                productID: product.id,
                displayName: product.displayName,
                percentOfWeekly: product.percentOfPool,
                colorToken: product.colorToken,
                isBeforeReset: false
            )
        }
    }

    /// Proportional split of a total when product-level deltas are unavailable.
    ///
    /// Uses the current product mix only as weights for the *delta*, not as absolute
    /// week-to-date amounts. When no products exist, label as "other" (never Build).
    private static func distribute(total: Double, products: [ProductUsage]) -> [DailyUsageSegment] {
        let visible = products.filter { $0.percentOfPool > 0.05 }
        let sum = visible.reduce(0.0) { $0 + $1.percentOfPool }
        guard total > 0.05 else { return [] }

        if visible.isEmpty || sum < 0.05 {
            return [
                DailyUsageSegment(
                    productID: "other",
                    displayName: "Other",
                    percentOfWeekly: total,
                    colorToken: .other,
                    isBeforeReset: false
                )
            ]
        }

        return ProductCatalog.sortForDisplay(visible).compactMap { product in
            let share = product.percentOfPool / sum
            let percent = total * share
            guard percent > 0.05 else { return nil }
            return DailyUsageSegment(
                productID: product.id,
                displayName: product.displayName,
                percentOfWeekly: percent,
                colorToken: product.colorToken,
                isBeforeReset: false
            )
        }
    }
}
