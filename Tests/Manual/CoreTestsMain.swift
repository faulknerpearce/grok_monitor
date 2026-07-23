import Foundation

@main
struct CoreTestsMain {
    static func main() throws {
        func assertTrue(_ cond: Bool, _ msg: String) throws {
            if !cond {
                fputs("FAIL: \(msg)\n", stderr)
                throw TestFailure(msg)
            }
            print("PASS: \(msg)")
        }

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

        guard let snap = UsageResponseParser.parseJSON(json, accountEmail: nil) else {
            throw TestFailure("parse fixture")
        }
        try assertTrue(abs(snap.usedPercent - 35) < 0.01, "usedPercent")
        try assertTrue(abs(snap.remainingPercent - 65) < 0.01, "remainingPercent")
        try assertTrue(snap.products.count == 3, "product count")
        try assertTrue(snap.products[0].colorToken == .build, "build color")

        let rem = WeeklyUsageSnapshot(usedPercent: 40)
        try assertTrue(abs(rem.remainingPercent - 60) < 0.01, "remaining default")

        let cli = """
        {
          "monthlyLimit": { "val": 1000 },
          "usage": { "totalUsed": { "val": 350 } },
          "billingCycle": { "billingPeriodEnd": "2026-07-16T20:25:00Z" }
        }
        """.data(using: .utf8)!
        guard let cliSnap = UsageResponseParser.parseCLIBilling(cli, accountEmail: "a@b.com") else {
            throw TestFailure("cli parse")
        }
        try assertTrue(abs(cliSnap.usedPercent - 35) < 0.01, "cli usedPercent")
        try assertTrue(cliSnap.accountEmail == "a@b.com", "cli email")

        let csv = try ExportService.export([.preview], format: .csv)
        let csvText = String(data: csv, encoding: .utf8)!
        try assertTrue(csvText.contains("fetchedAt,usedPercent"), "csv header")
        try assertTrue(csvText.contains("build:25"), "csv products")

        let jdata = try ExportService.export([.preview], format: .json)
        try assertTrue((try JSONSerialization.jsonObject(with: jdata)) is [Any], "json array")

        try assertTrue(ProductColor.from(productID: "build") == .build, "color map build")
        try assertTrue(ProductColor.from(productID: "API") == .api, "color map api")

        let byProduct = """
        { "usedPercent": 35, "byProduct": { "build": 25, "api": 9, "chat": 1 } }
        """.data(using: .utf8)!
        guard let mapped = UsageResponseParser.parseJSON(byProduct, accountEmail: nil) else {
            throw TestFailure("byProduct parse")
        }
        try assertTrue(mapped.products.count == 3, "byProduct count")

        // Live GetGrokCreditsConfig sample (Chat 23% + Build 13% = 36% used).
        let grpcHex = "000000005f0a5d0d0000104212001a00220b08b1debfd20610b8efb07f2a0b08b1d3e4d20610b8efb07f3a070804150000b8413a07080215000050413a020806421c0802120b08b1debfd20610b8efb07f1a0b08b1d3e4d20610b8efb07f580162006801800000000f677270632d7374617475733a300d0a"
        let grpcData = Data(hexString: grpcHex)!
        let grpc = try GRPCWebParser.parseUsage(grpcData)
        try assertTrue(abs((grpc.usedPercent ?? -1) - 36) < 0.01, "grpc usedPercent")
        try assertTrue(grpc.products.count == 2, "grpc product count")
        try assertTrue(grpc.products.contains(where: { $0.id == "chat" && abs($0.percentOfPool - 23) < 0.01 }), "grpc chat")
        try assertTrue(grpc.products.contains(where: { $0.id == "build" && abs($0.percentOfPool - 13) < 0.01 }), "grpc build")

        let previewWeek = DailyUsageBuilder.preview()
        try assertTrue(previewWeek.days.count == 7, "daily week days")
        try assertTrue(previewWeek.hasDailyData, "daily has data")
        try assertTrue(previewWeek.days.allSatisfy { !$0.isResetDay }, "no split reset bars")
        try assertTrue(previewWeek.resetCaption != nil, "preview reset caption")
        try assertTrue(abs(DailyUsageBuilder.fillFraction(forDayUsage: 10) - 10.0 / (100.0 / 7.0)) < 0.001, "daily cap math")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        let now = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let resetsAt = ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z")!
        let bounds = DailyUsageBuilder.billingPeriodWeekBounds(
            resetsAt: resetsAt,
            weekOffset: 0,
            calendar: cal,
            now: now
        )
        try assertTrue(cal.component(.weekday, from: bounds.start) == 5, "period starts Thursday")
        try assertTrue(cal.component(.weekday, from: bounds.end) == 4, "period ends Wednesday")

        print("ALL TESTS PASSED")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
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
