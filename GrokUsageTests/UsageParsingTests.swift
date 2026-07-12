import XCTest
@testable import GrokUsage

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
        cal.firstWeekday = 2
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            return XCTFail("date math")
        }

        let products = [
            ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 20),
            ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 10)
        ]
        let history = [
            WeeklyUsageSnapshot(
                fetchedAt: yesterday.addingTimeInterval(3600 * 12),
                usedPercent: 10,
                products: products
            ),
            WeeklyUsageSnapshot(
                fetchedAt: today.addingTimeInterval(3600 * 10),
                usedPercent: 30,
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
        XCTAssertEqual(week.days.count, 7)
        XCTAssertTrue(week.hasDailyData)
        let todayDay = week.days.first { cal.isDate($0.dayStart, inSameDayAs: today) }
        XCTAssertNotNil(todayDay)
        // Today should reflect ~20% delta (30 - 10), split across products.
        XCTAssertEqual(todayDay?.totalPercent ?? 0, 20, accuracy: 0.2)
    }

    func testDailyUsageAttributesToTodayWhenNoHistory() {
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
        XCTAssertTrue(week.hasDailyData)
        XCTAssertTrue(week.isEstimated)
        let today = week.days.first { cal.isDate($0.dayStart, inSameDayAs: now) }
        XCTAssertEqual(today?.totalPercent ?? 0, 39, accuracy: 0.2)
        // Prior days stay empty — do not invent usage before tracking started.
        let prior = week.days.filter { !cal.isDate($0.dayStart, inSameDayAs: now) }
        XCTAssertTrue(prior.allSatisfy(\.segments.isEmpty))
    }

    func testDailyCapFillFraction() {
        // 10% of weekly pool / (100/7) ≈ 0.70 of the daily track.
        let fraction = DailyUsageBuilder.fillFraction(forDayUsage: 10)
        XCTAssertEqual(fraction, 10.0 / (100.0 / 7.0), accuracy: 0.001)
        // Over daily cap clamps to full track.
        XCTAssertEqual(DailyUsageBuilder.fillFraction(forDayUsage: 21), 1.0, accuracy: 0.001)
        XCTAssertEqual(DailyUsageBuilder.fillFraction(forDayUsage: 0), 0, accuracy: 0.001)
    }

    func testBillingWeekBoundsFromResetsAt() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        // Reset Jul 16 → week ends Jul 15, starts Jul 9.
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T20:25:00Z")!
        let bounds = DailyUsageBuilder.billingWeekBounds(
            resetsAt: resetsAt,
            weekOffset: 0,
            calendar: cal,
            now: resetsAt.addingTimeInterval(-3 * 24 * 3600)
        )
        let startDay = cal.component(.day, from: bounds.start)
        let endDay = cal.component(.day, from: bounds.end)
        XCTAssertEqual(startDay, 9)
        XCTAssertEqual(endDay, 15)
        XCTAssertEqual(cal.dateComponents([.day], from: bounds.start, to: bounds.end).day, 6)
    }

    func testServerDailySeriesPreferred() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        let weekStart = DailyUsageBuilder.billingWeekBounds(
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
        let week = DailyUsageBuilder.preview()
        XCTAssertEqual(week.days.count, 7)
        XCTAssertTrue(week.showsBeforeReset)
        XCTAssertTrue(week.hasDailyData)
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
