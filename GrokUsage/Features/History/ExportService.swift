import Foundation

enum ExportService {
    enum Format {
        case csv
        case json
    }

    static func export(_ snapshots: [WeeklyUsageSnapshot], format: Format) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let payload = snapshots.map { ExportRow(from: $0) }
            return try encoder.encode(payload)
        case .csv:
            var lines = ["fetchedAt,usedPercent,remainingPercent,resetsAt,products,extraCredits,accountEmail"]
            let iso = ISO8601DateFormatter()
            for snap in snapshots {
                let products = snap.products
                    .map { "\($0.id):\($0.percentOfPool)" }
                    .joined(separator: "|")
                let resets = snap.resetsAt.map { iso.string(from: $0) } ?? ""
                let credits = snap.extraCreditsBalance.map { "\($0)" } ?? ""
                let email = snap.accountEmail ?? ""
                lines.append([
                    iso.string(from: snap.fetchedAt),
                    String(format: "%.2f", snap.usedPercent),
                    String(format: "%.2f", snap.remainingPercent),
                    csvEscape(resets),
                    csvEscape(products),
                    csvEscape(credits),
                    csvEscape(email)
                ].joined(separator: ","))
            }
            return Data(lines.joined(separator: "\n").utf8)
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private struct ExportRow: Encodable {
        var fetchedAt: Date
        var usedPercent: Double
        var remainingPercent: Double
        var resetsAt: Date?
        var products: [ProductUsage]
        var extraCreditsBalance: Decimal?
        var accountEmail: String?

        init(from snap: WeeklyUsageSnapshot) {
            fetchedAt = snap.fetchedAt
            usedPercent = snap.usedPercent
            remainingPercent = snap.remainingPercent
            resetsAt = snap.resetsAt
            products = snap.products
            extraCreditsBalance = snap.extraCreditsBalance
            accountEmail = snap.accountEmail
        }
    }
}
