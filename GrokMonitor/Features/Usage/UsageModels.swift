import Foundation

/// Semantic color tokens for product segments in the usage bar.
enum ProductColor: String, Codable, CaseIterable, Sendable {
    case build
    case api
    case chat
    case imagine
    case voice
    case other

    static func from(productID: String) -> ProductColor {
        switch productID.lowercased() {
        case "build", "grok_build", "grok-build", "grok build":
            return .build
        case "api":
            return .api
        case "chat", "grok", "text":
            return .chat
        case "imagine", "image", "video", "media":
            return .imagine
        case "voice":
            return .voice
        default:
            return .other
        }
    }

    /// Canonical sRGB components shared by SwiftUI and AppKit renderers.
    var sRGB: (red: Double, green: Double, blue: Double, alpha: Double) {
        switch self {
        case .chat: return (0.11, 0.38, 0.82, 1) // navy — Chat
        case .build: return (0.55, 0.78, 1.0, 1) // sky blue — Grok Build
        case .voice: return (0.40, 0.55, 0.82, 1) // mid blue — Voice
        case .api: return (0.22, 0.32, 0.48, 1) // dark navy — API
        case .imagine: return (0.75, 0.90, 1.0, 1) // pale blue — Imagine
        case .other: return (0.45, 0.45, 0.45, 1)
        }
    }
}

/// Canonical product IDs, labels, and stable sort order for UI surfaces.
enum ProductCatalog {
    /// Preference toggle order.
    static let knownIDs = ["build", "api", "chat", "imagine", "voice"]
    /// Visual priority for bars / chips (chat first).
    static let displayOrder = ["chat", "build", "voice", "api", "imagine"]

    static func displayName(for id: String) -> String {
        switch id.lowercased() {
        case "build": return "Grok Build"
        case "api": return "API"
        case "chat": return "Chat"
        case "imagine": return "Imagine"
        case "voice": return "Voice"
        default: return id.capitalized
        }
    }

    static func shortName(for id: String) -> String {
        switch id.lowercased() {
        case "build": return "Build"
        case "api": return "API"
        case "chat": return "Chat"
        case "imagine": return "Imagine"
        case "voice": return "Voice"
        default: return displayName(for: id)
        }
    }

    static func sortForDisplay(_ products: [ProductUsage]) -> [ProductUsage] {
        products.sorted { a, b in
            let ai = displayOrder.firstIndex(of: a.id.lowercased()) ?? 99
            let bi = displayOrder.firstIndex(of: b.id.lowercased()) ?? 99
            return ai < bi
        }
    }
}

/// A single product's contribution to the weekly SuperGrok usage pool.
struct ProductUsage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var percentOfPool: Double
    var colorToken: ProductColor

    init(id: String, displayName: String, percentOfPool: Double, colorToken: ProductColor? = nil) {
        self.id = id
        self.displayName = displayName
        self.percentOfPool = percentOfPool
        self.colorToken = colorToken ?? ProductColor.from(productID: id)
    }
}

// MARK: - Daily use (Settings → Usage style)

/// One product slice of a single day's contribution to the weekly pool.
struct DailyUsageSegment: Identifiable, Hashable, Sendable {
    var id: String { "\(productID)-\(isBeforeReset ? "pre" : "post")" }
    var productID: String
    var displayName: String
    var percentOfWeekly: Double
    var colorToken: ProductColor
    /// Usage attributed to the prior billing period that ended mid-day.
    var isBeforeReset: Bool
}

/// One calendar day in the daily-use chart.
struct DailyUsageDay: Identifiable, Hashable, Sendable {
    var id: Date { dayStart }
    var dayStart: Date
    var weekdaySymbol: String
    /// Day-of-month for axis labels (e.g. "16").
    var dayOfMonth: String
    var segments: [DailyUsageSegment]
    var isToday: Bool
    /// True when a billing-period rollover or mid-period rebase started on this day.
    var isAfterReset: Bool
    /// True when `resetsAt` falls on this calendar day (mid-week pool reset marker).
    var isResetDay: Bool
    /// Exact reset time when this is the reset day.
    var resetAt: Date?

    var totalPercent: Double {
        segments.reduce(0) { $0 + $1.percentOfWeekly }
    }
}

/// Legend entry for the daily use chart.
struct DailyUsageLegendItem: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var colorToken: ProductColor
}

/// Server-provided daily usage row (when a daily API is discovered).
struct DailyUsageSnapshot: Identifiable, Hashable, Codable, Sendable {
    var dayStart: Date
    var percentOfWeekly: Double
    var products: [ProductUsage]

    var id: Date { dayStart }
}

/// Billing-period window for the daily use chart (e.g. Thu→Wed when the pool resets Thursday).
struct DailyUsageWeek: Hashable, Sendable {
    var weekStart: Date
    var weekEnd: Date
    var days: [DailyUsageDay]
    /// Products that appear in any day (for legend).
    var legendProducts: [DailyUsageLegendItem]
    var showsBeforeReset: Bool
    /// True when at least one day has a real usage delta (not empty fallback).
    var hasDailyData: Bool
    /// True when fewer than two in-week samples exist (daily bars not yet day-over-day).
    var isEstimated: Bool
    /// Short caption for when this period’s pool resets (e.g. "Resets Thu 2:25 PM").
    var resetCaption: String?

    /// Chronological days for the chart (billing period start → +6 days).
    var displayDays: [DailyUsageDay] {
        days
    }

    var rangeLabel: String {
        let f = Date.FormatStyle().month(.abbreviated).day()
        return "\(weekStart.formatted(f)) – \(weekEnd.formatted(f))"
    }
}

/// Snapshot of the weekly SuperGrok usage pool at a point in time.
struct WeeklyUsageSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var fetchedAt: Date
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var products: [ProductUsage]
    var extraCreditsBalance: Decimal?
    var accountEmail: String?
    var rawPayload: Data?
    /// Per-day series from server when available (not required for Codable round-trip).
    var dailySeries: [DailyUsageSnapshot]

    init(
        id: UUID = UUID(),
        fetchedAt: Date = Date(),
        usedPercent: Double,
        remainingPercent: Double? = nil,
        resetsAt: Date? = nil,
        products: [ProductUsage] = [],
        extraCreditsBalance: Decimal? = nil,
        accountEmail: String? = nil,
        rawPayload: Data? = nil,
        dailySeries: [DailyUsageSnapshot] = []
    ) {
        self.id = id
        self.fetchedAt = fetchedAt
        let clampedUsed = max(0, min(100, usedPercent))
        self.usedPercent = clampedUsed
        self.remainingPercent = remainingPercent ?? max(0, min(100, 100 - clampedUsed))
        self.resetsAt = resetsAt
        self.products = products
        self.extraCreditsBalance = extraCreditsBalance
        self.accountEmail = accountEmail
        self.rawPayload = rawPayload
        self.dailySeries = dailySeries
    }

    /// Products with non-zero contribution, preserving API order.
    var visibleProducts: [ProductUsage] {
        products.filter { $0.percentOfPool > 0.05 }
    }

    static let preview = WeeklyUsageSnapshot(
        usedPercent: 35,
        remainingPercent: 65,
        resetsAt: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
        products: [
            ProductUsage(id: "build", displayName: "Grok Build", percentOfPool: 25),
            ProductUsage(id: "api", displayName: "API", percentOfPool: 9),
            ProductUsage(id: "chat", displayName: "Chat", percentOfPool: 1)
        ],
        extraCreditsBalance: nil,
        accountEmail: "user@example.com"
    )
}

enum UsageClientError: LocalizedError, Equatable {
    case notSignedIn
    case unauthorized
    case httpStatus(Int, String)
    case decodingFailed(String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to grok.com to load usage."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case let .httpStatus(code, body):
            return "Usage request failed (HTTP \(code)): \(body)"
        case let .decodingFailed(detail):
            return "Could not parse usage response: \(detail)"
        case .emptyResponse:
            return "Empty usage response from Grok."
        case let .network(message):
            return message
        }
    }
}
