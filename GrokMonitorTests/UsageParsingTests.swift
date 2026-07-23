import XCTest
@testable import GrokMonitor

final class UsageParsingTests: XCTestCase {
    func testParseFixtureJSON() throws {
        let json = """
        {
          "usedPercent": 35,
          "remainingPercent": 65,
          "resetsAt": "2026-07-16T20:25:00Z",
          "products": [
            { "id": "build", "displayName": "Grok Build", "percentOfPool": 25 },
            { "id": "api", "displayName": "API", "percentOfPool": 9 },
            { "id": "chat", "displayName": "Chat", "percentOfPool": 1 }
          ]
        }
        """.data(using: .utf8)!

        let snap = try XCTUnwrap(UsageResponseParser.parseJSON(json, accountEmail: nil))
        XCTAssertEqual(snap.usedPercent, 35, accuracy: 0.01)
        XCTAssertEqual(snap.remainingPercent, 65, accuracy: 0.01)
        XCTAssertEqual(snap.products.count, 3)
        XCTAssertEqual(snap.products[0].id, "build")
        XCTAssertEqual(snap.products[0].colorToken, .build)
    }

    func testRemainingDefaultsFromUsed() {
        let snap = WeeklyUsageSnapshot(usedPercent: 40)
        XCTAssertEqual(snap.remainingPercent, 60, accuracy: 0.01)
    }

    func testCLIBillingParse() throws {
        let json = """
        {
          "monthlyLimit": { "val": 1000 },
          "usage": { "totalUsed": { "val": 350 } },
          "billingCycle": { "billingPeriodEnd": "2026-07-16T20:25:00Z" }
        }
        """.data(using: .utf8)!
        let snap = try XCTUnwrap(UsageResponseParser.parseCLIBilling(json, accountEmail: "a@b.com"))
        XCTAssertEqual(snap.usedPercent, 35, accuracy: 0.01)
        XCTAssertEqual(snap.accountEmail, "a@b.com")
        XCTAssertNotNil(snap.resetsAt)
    }

    func testProductColorMapping() {
        XCTAssertEqual(ProductColor.from(productID: "build"), .build)
        XCTAssertEqual(ProductColor.from(productID: "API"), .api)
        XCTAssertEqual(ProductColor.from(productID: "imagine"), .imagine)
    }

    func testExportCSVContainsHeader() throws {
        let data = try ExportService.export([.preview], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("fetchedAt,usedPercent"))
        XCTAssertTrue(text.contains("build:25"))
    }

    func testExportJSONRoundTrip() throws {
        let data = try ExportService.export([.preview], format: .json)
        let obj = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(obj is [Any])
    }

    func testByProductMapParse() throws {
        let json = """
        {
          "usedPercent": 35,
          "byProduct": { "build": 25, "api": 9, "chat": 1 }
        }
        """.data(using: .utf8)!
        let snap = try XCTUnwrap(UsageResponseParser.parseJSON(json, accountEmail: nil))
        XCTAssertEqual(snap.products.count, 3)
    }

    func testGRPCProductBreakdown() throws {
        let grpcHex = "000000005f0a5d0d0000104212001a00220b08b1debfd20610b8efb07f2a0b08b1d3e4d20610b8efb07f3a070804150000b8413a07080215000050413a020806421c0802120b08b1debfd20610b8efb07f1a0b08b1d3e4d20610b8efb07f580162006801800000000f677270632d7374617475733a300d0a"
        let data = try XCTUnwrap(Data(hexString: grpcHex))
        let parsed = try GRPCWebParser.parseUsage(data)
        XCTAssertEqual(parsed.usedPercent ?? -1, 36, accuracy: 0.01)
        XCTAssertEqual(parsed.products.count, 2)
        XCTAssertTrue(parsed.products.contains { $0.id == "chat" && abs($0.percentOfPool - 23) < 0.01 })
        XCTAssertTrue(parsed.products.contains { $0.id == "build" && abs($0.percentOfPool - 13) < 0.01 })
    }

    func testDailyUsageBuilderDeltas() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Fixed mid-week pair so both samples sit inside the billing window.
        let now = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            return XCTFail("date math")
        }
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!

        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 12),
                usedPercent: 10,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 7),
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 3)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 10),
                usedPercent: 30,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 20),
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 10)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        XCTAssertEqual(week.days.count, 7)
        XCTAssertTrue(week.hasDailyData)
        XCTAssertFalse(week.isEstimated)

        let yesterdayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: yesterday) }
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        // First sample day stays empty; today is the day-over-day delta only.
        XCTAssertEqual(yesterdayDay?.totalPercent ?? 0, 0, accuracy: 0.2)
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 20, accuracy: 0.2)
        XCTAssertEqual(todayDay?.segments.count, 2)
    }

    func testDailyUsageOnlyShowsProductsThatGrew() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-12T12:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            return XCTFail("date math")
        }

        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 18),
                usedPercent: 39,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 23),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 13),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 3)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 10),
                usedPercent: 42,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 26),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 13),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 3)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            calendar: cal,
            now: now
        )

        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 3, accuracy: 0.2)
        XCTAssertEqual(todayDay?.segments.count, 1)
        XCTAssertEqual(todayDay?.segments.first?.productID, "chat")
        // Legend for the week still includes yesterday’s products, but today’s bar is chat-only.
        XCTAssertTrue(todayDay?.segments.allSatisfy { $0.percentOfWeekly > 0 } ?? false)
    }

    func testDailyUsageShowsYesterdayAfterDayRollover() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        // Fixed Sunday so billing week (Mon–Sun) and calendar week align without resetsAt.
        let now = ISO8601DateFormatter().date(from: "2026-07-12T10:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            return XCTFail("date math")
        }

        let products = [
            ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 23),
            ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16)
        ]
        // App tracked all day Saturday; Sunday morning has not used more yet.
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 20),
                usedPercent: 39,
                products: products
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 9),
                usedPercent: 39,
                products: products
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            calendar: cal,
            now: now
        )

        let yesterdayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: yesterday) }
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        // First sample is a baseline only; flat day-over-day → empty bars.
        XCTAssertEqual(yesterdayDay?.totalPercent ?? 0, 0, accuracy: 0.2)
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 0, accuracy: 0.2)
        XCTAssertFalse(week.isEstimated)
        XCTAssertFalse(week.hasDailyData)
    }

    func testDailyUsageEmptyUntilSecondSampleDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-11T18:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: now,
                usedPercent: 39,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 23),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        // Single sample: do not paint week-to-date product % onto "today".
        XCTAssertFalse(week.hasDailyData)
        XCTAssertTrue(week.isEstimated)
        XCTAssertTrue(week.days.allSatisfy(\.segments.isEmpty))
    }

    func testDailyUsageExcludesFlatBuildFromToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard
            let day1 = cal.date(byAdding: .day, value: -2, to: today),
            let day2 = cal.date(byAdding: .day, value: -1, to: today)
        else {
            return XCTFail("date math")
        }
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: day1.addingTimeInterval(3600 * 20),
                usedPercent: 46,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 27),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 3)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: day2.addingTimeInterval(3600 * 14),
                usedPercent: 51,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 31),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 4)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 8),
                usedPercent: 58,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 34),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 7),
                    ProductUsage(id: "voice", displayName: "Voice", percentOfPool: 1)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 7, accuracy: 0.2)
        XCTAssertFalse(todayDay?.segments.contains { $0.productID == "build" } ?? true)
        XCTAssertTrue(todayDay?.segments.contains { $0.productID == "chat" } ?? false)
        XCTAssertTrue(todayDay?.segments.contains { $0.productID == "api" } ?? false)
        XCTAssertTrue(todayDay?.segments.contains { $0.productID == "voice" } ?? false)
    }

    /// Mid-period server recalibration: used% drops but `resetsAt` stays the same.
    /// Invalidates pre-rebase samples so prior days do not keep inflated bars while
    /// the rebased week-to-date is painted on the recalibration day.
    func testDailyUsageMidPeriodRecalibrationRebasesOntoThatDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-14T22:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard
            let yesterday = cal.date(byAdding: .day, value: -1, to: today),
            let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)
        else {
            return XCTFail("date math")
        }
        // Same billing period as live history (reset still Jul 16).
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: twoDaysAgo.addingTimeInterval(3600 * 18),
                usedPercent: 51,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 31),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 16),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 4)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 12),
                usedPercent: 71,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 34),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 28),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 7),
                    ProductUsage(id: "voice", displayName: "Voice", percentOfPool: 2)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 16),
                usedPercent: 28,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 1),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 20),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 7)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        let yesterdayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: yesterday) }
        let olderDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: twoDaysAgo) }
        // Drop prior days; start tracking on the reset day with current week-to-date.
        XCTAssertTrue(todayDay?.isAfterReset ?? false)
        XCTAssertEqual(olderDay?.totalPercent ?? 0, 0, accuracy: 0.2)
        XCTAssertEqual(yesterdayDay?.totalPercent ?? 0, 0, accuracy: 0.2)
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 28, accuracy: 0.5)
        XCTAssertTrue(todayDay?.segments.contains { $0.productID == "build" } ?? false)
        XCTAssertTrue(week.isEstimated)
    }

    /// Real period rollover: used% drops AND sample `resetsAt` advances — mark after-reset
    /// and attribute the new period total to that sample day.
    func testDailyUsageRealResetShowsPostResetUsage() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Hold the chart on the pre-reset billing window so both samples stay in-range.
        let now = ISO8601DateFormatter().date(from: "2026-07-15T20:00:00Z")!
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            return XCTFail("date math")
        }
        let oldResets = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let newResets = ISO8601DateFormatter().date(from: "2026-07-23T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 12),
                usedPercent: 90,
                resetsAt: oldResets,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 90)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 8),
                usedPercent: 12,
                resetsAt: newResets,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 8),
                    ProductUsage(id: "api", displayName: "API", percentOfPool: 4)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            // Window Jul 9–15 (day before oldResets), not the post-reset week.
            resetsAt: oldResets,
            calendar: cal,
            now: now
        )
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        XCTAssertNotNil(todayDay)
        XCTAssertTrue(todayDay?.isAfterReset ?? false)
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 12, accuracy: 0.2)
        XCTAssertTrue(todayDay?.segments.contains { $0.productID == "chat" } ?? false)
    }

    func testDailyUsageIgnoresPriorBillingPeriodSample() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        // Prior period end (before week start Jul 9) plus a single in-week sample.
        let priorPeriod = ISO8601DateFormatter().date(from: "2026-07-08T18:00:00Z")!
        let inWeek = ISO8601DateFormatter().date(from: "2026-07-13T10:00:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: priorPeriod,
                usedPercent: 90,
                resetsAt: ISO8601DateFormatter().date(from: "2026-07-09T18:57:00Z"),
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 90)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: inWeek,
                usedPercent: 20,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 12),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 8)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        // Prior period must not create a giant before-reset bar; single in-week sample → empty.
        XCTAssertFalse(week.showsBeforeReset)
        XCTAssertTrue(week.days.allSatisfy(\.segments.isEmpty))
        XCTAssertTrue(week.isEstimated)
    }

    func testDailyCapFillFraction() {
        // 10% of weekly pool / (100/7) ≈ 0.70 of the daily track.
        let fraction = DailyUsageBuilder.fillFraction(forDayUsage: 10)
        XCTAssertEqual(fraction, 10.0 / (100.0 / 7.0), accuracy: 0.001)
        // Over daily cap clamps to full track.
        XCTAssertEqual(DailyUsageBuilder.fillFraction(forDayUsage: 21), 1.0, accuracy: 0.001)
        XCTAssertEqual(DailyUsageBuilder.fillFraction(forDayUsage: 0), 0, accuracy: 0.001)
    }

    func testBillingPeriodWeekStartsOnPeriodStartDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Reset Thu Jul 16 → period bars Thu Jul 9 – Wed Jul 15 (mid-period).
        let now = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let bounds = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: resetsAt,
            weekOffset: 0,
            calendar: cal,
            now: now
        )
        XCTAssertEqual(cal.component(.weekday, from: bounds.start), 5) // Thursday
        XCTAssertEqual(cal.component(.weekday, from: bounds.end), 4) // Wednesday
        XCTAssertEqual(cal.component(.day, from: bounds.start), 9)
        XCTAssertEqual(cal.component(.day, from: bounds.end), 15)
        XCTAssertEqual(cal.dateComponents([.day], from: bounds.start, to: bounds.end).day, 6)

        // Still before reset on that Thursday morning: stay on old week (one Thursday only).
        let resetMorning = ISO8601DateFormatter().date(from: "2026-07-16T12:00:00Z")!
        let onResetDayMorning = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: resetsAt,
            weekOffset: 0,
            calendar: cal,
            now: resetMorning
        )
        XCTAssertEqual(cal.component(.day, from: onResetDayMorning.start), 9)
        XCTAssertEqual(cal.component(.day, from: onResetDayMorning.end), 15)
        XCTAssertEqual(cal.dateComponents([.day], from: onResetDayMorning.start, to: onResetDayMorning.end).day, 6)

        // After reset fires (API may lag): roll entire window — single new Thursday, not two.
        let afterReset = ISO8601DateFormatter().date(from: "2026-07-16T20:00:00Z")!
        let rolled = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: resetsAt,
            weekOffset: 0,
            calendar: cal,
            now: afterReset
        )
        XCTAssertEqual(cal.component(.day, from: rolled.start), 16)
        XCTAssertEqual(cal.component(.day, from: rolled.end), 22)
        XCTAssertEqual(cal.dateComponents([.day], from: rolled.start, to: rolled.end).day, 6)
        // Only one Thursday in the 7-day window (the start).
        let thuCount = (0..<7).filter { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: rolled.start) else { return false }
            return cal.component(.weekday, from: d) == 5
        }.count
        XCTAssertEqual(thuCount, 1)

        // After API advances resetsAt: same new-period window.
        let nextResets = ISO8601DateFormatter().date(from: "2026-07-23T18:57:00Z")!
        let next = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: nextResets,
            weekOffset: 0,
            calendar: cal,
            now: afterReset
        )
        XCTAssertEqual(cal.component(.day, from: next.start), 16)
        XCTAssertEqual(cal.component(.day, from: next.end), 22)

        let previous = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: resetsAt,
            weekOffset: -1,
            calendar: cal,
            now: now
        )
        XCTAssertEqual(cal.component(.day, from: previous.start), 2)
        XCTAssertEqual(cal.component(.day, from: previous.end), 8)
    }

    func testPeriodStartThursdayShowsUsage() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // New period: resets next Thu Jul 23 → window starts Thu Jul 16.
        let now = ISO8601DateFormatter().date(from: "2026-07-16T20:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-23T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: now,
                usedPercent: 12,
                resetsAt: resetsAt,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 8),
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 4)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        XCTAssertEqual(cal.component(.weekday, from: week.weekStart), 5) // Thursday
        let thursday = week.days.first { cal.isDate($0.dayStart, inSameDayAs: now) }
        XCTAssertEqual(thursday?.totalPercent ?? 0, 12, accuracy: 0.5)
        XCTAssertFalse(thursday?.segments.isEmpty ?? true)
    }

    func testBillingPeriodResetCaptionWithoutHighlightingBars() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let week = DailyUsageBuilder.week(
            history: [],
            current: WeeklyUsageSnapshot(fetchedAt: now, usedPercent: 10, resetsAt: resetsAt),
            weekOffset: 0,
            resetsAt: resetsAt,
            calendar: cal,
            now: now
        )
        // Period starts Thursday; no bar is marked as a split reset day.
        XCTAssertEqual(cal.component(.weekday, from: week.weekStart), 5)
        XCTAssertTrue(week.days.allSatisfy { !$0.isResetDay })
        XCTAssertNotNil(week.resetCaption)
        XCTAssertTrue(week.resetCaption?.contains("Resets") ?? false)
    }

    func testCrossResetDeltasDoNotInventDropBar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Calendar week Mon Jul 13 – Sun Jul 19; reset Thu Jul 16.
        let now = ISO8601DateFormatter().date(from: "2026-07-17T15:00:00Z")! // Friday
        let wed = ISO8601DateFormatter().date(from: "2026-07-15T18:00:00Z")!
        let fri = ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z")!
        let oldResets = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let newResets = ISO8601DateFormatter().date(from: "2026-07-23T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: wed,
                usedPercent: 90,
                resetsAt: oldResets,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 90)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: fri,
                usedPercent: 8,
                resetsAt: newResets,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 8)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: 0,
            resetsAt: newResets,
            calendar: cal,
            now: now
        )
        let friDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: fri) }
        let wedDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: wed) }
        // Whole week has flipped to the new period; Wed (old period) is outside the window.
        XCTAssertNil(wedDay)
        // Single post-reset sample day: no invented 90→8 drop bar; wait for a second day.
        XCTAssertEqual(friDay?.totalPercent ?? 0, 0, accuracy: 0.5)
        XCTAssertFalse(friDay?.segments.contains { $0.percentOfWeekly > 50 } ?? true)
        XCTAssertTrue(week.isEstimated)
    }

    /// After weekly rollover, chevron-left (`weekOffset: -1`) must still show last period’s bars.
    func testPreviousWeekKeepsPriorPeriodDailyUsageAfterRollover() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Live week is the new period (started Thu Jul 16); next reset Jul 23.
        let now = ISO8601DateFormatter().date(from: "2026-07-17T15:00:00Z")!
        let mon = ISO8601DateFormatter().date(from: "2026-07-13T18:00:00Z")!
        let tue = ISO8601DateFormatter().date(from: "2026-07-14T18:00:00Z")!
        let wed = ISO8601DateFormatter().date(from: "2026-07-15T18:00:00Z")!
        let fri = ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z")!
        let oldResets = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let newResets = ISO8601DateFormatter().date(from: "2026-07-23T18:57:00Z")!
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: mon,
                usedPercent: 40,
                resetsAt: oldResets,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 40)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: tue,
                usedPercent: 55,
                resetsAt: oldResets,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 55)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: wed,
                usedPercent: 70,
                resetsAt: oldResets,
                products: [
                    ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 70)
                ]
            ),
            WeeklyUsageSnapshot(
                fetchedAt: fri,
                usedPercent: 8,
                resetsAt: newResets,
                products: [
                    ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 8)
                ]
            )
        ]
        let week = DailyUsageBuilder.week(
            history: history,
            current: history.last,
            weekOffset: -1,
            resetsAt: newResets,
            calendar: cal,
            now: now
        )
        // Prior billing window: Thu Jul 9 – Wed Jul 15.
        XCTAssertEqual(cal.component(.day, from: week.weekStart), 9)
        XCTAssertEqual(cal.component(.day, from: week.weekEnd), 15)
        let tueDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: tue) }
        let wedDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: wed) }
        // Day-over-day growth from local samples must survive rollover when browsing back.
        XCTAssertEqual(tueDay?.totalPercent ?? 0, 15, accuracy: 0.5)
        XCTAssertEqual(wedDay?.totalPercent ?? 0, 15, accuracy: 0.5)
        XCTAssertTrue(week.hasDailyData)
    }

    func testServerDailySeriesPreferred() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        let weekStart = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: nil,
            weekOffset: 0,
            calendar: cal,
            now: now
        ).start
        guard let wed = cal.date(byAdding: .day, value: 2, to: weekStart) else {
            return XCTFail("date math")
        }
        let server = [
            DailyUsageSnapshot(dayStart: wed, percentOfWeekly: 10, products: [
                ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 10)
            ])
        ]
        let week = DailyUsageBuilder.week(
            history: [],
            current: nil,
            serverDaily: server,
            weekOffset: 0,
            calendar: cal,
            now: now
        )
        XCTAssertTrue(week.hasDailyData)
        let wedDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: wed) }
        XCTAssertEqual(wedDay?.totalPercent ?? 0, 10, accuracy: 0.2)
    }

    func testDailyUsagePreviewHasSevenDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let week = DailyUsageBuilder.preview(calendar: cal)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertTrue(week.hasDailyData)
        XCTAssertTrue(week.days.allSatisfy { !$0.isResetDay })
        XCTAssertNotNil(week.resetCaption)
        // Billing period: first day is Thursday for the synthetic Jul 16 reset.
        XCTAssertEqual(cal.component(.weekday, from: week.weekStart), 5)
        XCTAssertEqual(cal.component(.weekday, from: week.weekEnd), 4)
    }
}

private extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var data = Data(capacity: chars.count / 2)
        var i = chars.startIndex
        while i < chars.endIndex {
            let next = chars.index(i, offsetBy: 2)
            guard let byte = UInt8(String(chars[i..<next]), radix: 16) else { return nil }
            data.append(byte)
            i = next
        }
        self = data
    }
}
