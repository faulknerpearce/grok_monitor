import Foundation
import Combine
import SwiftData
import os

@Model
final class UsageSnapshotRecord {
    @Attribute(.unique) var id: UUID
    var fetchedAt: Date
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var productsJSON: Data
    /// Stored as Double for SwiftData schema stability; domain model uses Decimal.
    var extraCredits: Double?
    var accountEmail: String?
    var rawPayload: Data?

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let logger = Logger(subsystem: "com.grokmonitor.app", category: "History")

    init(from snapshot: WeeklyUsageSnapshot) {
        self.id = snapshot.id
        self.fetchedAt = snapshot.fetchedAt
        self.usedPercent = snapshot.usedPercent
        self.remainingPercent = snapshot.remainingPercent
        self.resetsAt = snapshot.resetsAt
        if let data = try? Self.encoder.encode(snapshot.products) {
            self.productsJSON = data
        } else {
            Self.logger.error("Failed to encode products for snapshot \(snapshot.id)")
            self.productsJSON = Data()
        }
        self.extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        self.accountEmail = snapshot.accountEmail
        self.rawPayload = snapshot.rawPayload
    }

    func apply(_ snapshot: WeeklyUsageSnapshot) {
        fetchedAt = snapshot.fetchedAt
        usedPercent = snapshot.usedPercent
        remainingPercent = snapshot.remainingPercent
        resetsAt = snapshot.resetsAt
        if let data = try? Self.encoder.encode(snapshot.products) {
            productsJSON = data
        } else {
            Self.logger.error("Failed to encode products on apply for \(snapshot.id)")
        }
        extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        accountEmail = snapshot.accountEmail
        rawPayload = snapshot.rawPayload
    }

    func toSnapshot() -> WeeklyUsageSnapshot {
        let products: [ProductUsage]
        if let decoded = try? Self.decoder.decode([ProductUsage].self, from: productsJSON) {
            products = decoded
        } else {
            Self.logger.error("Failed to decode productsJSON for record \(self.id)")
            products = []
        }
        return WeeklyUsageSnapshot(
            id: id,
            fetchedAt: fetchedAt,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetsAt: resetsAt,
            products: products,
            extraCreditsBalance: extraCredits.map { Decimal($0) },
            accountEmail: accountEmail,
            rawPayload: rawPayload
        )
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.grokmonitor.app", category: "HistoryStore")

    private var container: ModelContainer?
    private var context: ModelContext?

    @Published private(set) var recent: [WeeklyUsageSnapshot] = []

    init(inMemory: Bool = false) {
        do {
            let config: ModelConfiguration
            if inMemory {
                config = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                let storeURL = Self.persistentStoreURL()
                config = ModelConfiguration(url: storeURL)
            }
            let container = try ModelContainer(for: UsageSnapshotRecord.self, configurations: config)
            self.container = container
            self.context = ModelContext(container)
            reload()
        } catch {
            Self.logger.error("SwiftData init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stable Application Support store so history survives the rename when migration succeeds.
    private static func persistentStoreURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("GrokMonitor", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("history.store")
        migrateLegacyStoreIfNeeded(to: storeURL, applicationSupportBase: base)
        return storeURL
    }

    /// Import pre-rename SwiftData (`com.grokusage.app` used `default.store`).
    /// Runs once, and also replaces a clearly smaller/newer empty store.
    private static func migrateLegacyStoreIfNeeded(to storeURL: URL, applicationSupportBase base: URL) {
        let fm = FileManager.default
        let flagKey = "didMigrateGrokUsageHistoryV1"
        let legacyCandidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Library/Containers/com.grokusage.app/Data/Library/Application Support/default.store"
                ),
            base.appendingPathComponent("default.store"),
            base.appendingPathComponent("GrokUsage/history.store"),
            base.appendingPathComponent("GrokUsage/default.store")
        ]

        guard let legacy = legacyCandidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            return
        }

        let legacySize = (try? fm.attributesOfItem(atPath: legacy.path)[.size] as? NSNumber)?.intValue ?? 0
        let currentExists = fm.fileExists(atPath: storeURL.path)
        let currentSize = currentExists
            ? ((try? fm.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber)?.intValue ?? 0)
            : 0

        let alreadyMigrated = UserDefaults.standard.bool(forKey: flagKey)
        let shouldReplace = !currentExists || currentSize + 2048 < legacySize
        guard shouldReplace else {
            if !alreadyMigrated { UserDefaults.standard.set(true, forKey: flagKey) }
            return
        }
        if alreadyMigrated && currentExists && currentSize >= legacySize {
            return
        }

        do {
            if currentExists {
                try fm.removeItem(at: storeURL)
            }
            for suffix in ["-shm", "-wal"] {
                let side = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.removeItem(at: side)
                }
            }
            try fm.copyItem(at: legacy, to: storeURL)
            for suffix in ["-shm", "-wal"] {
                let side = URL(fileURLWithPath: legacy.path + suffix)
                let dest = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.copyItem(at: side, to: dest)
                }
            }
            UserDefaults.standard.set(true, forKey: flagKey)
            logger.info("Migrated legacy history store from \(legacy.path, privacy: .public)")
        } catch {
            logger.error("History migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func append(_ snapshot: WeeklyUsageSnapshot) {
        guard let context else { return }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: snapshot.fetchedAt)

        if let last = recent.first,
           cal.isDate(last.fetchedAt, inSameDayAs: snapshot.fetchedAt),
           abs(last.usedPercent - snapshot.usedPercent) < 0.05,
           abs(last.fetchedAt.timeIntervalSince(snapshot.fetchedAt)) < 60
        {
            return
        }

        let sameDay = findRecords(on: dayStart, calendar: cal)
        if let existing = sameDay.first {
            existing.apply(snapshot)
            // Collapse legacy duplicates so each calendar day has one end-of-day row.
            for extra in sameDay.dropFirst() {
                context.delete(extra)
            }
            save(context: context)
            reload()
            return
        }

        context.insert(UsageSnapshotRecord(from: snapshot))
        save(context: context)
        reload()
    }

    func allSnapshots() -> [WeeklyUsageSnapshot] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<UsageSnapshotRecord>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { $0.toSnapshot() }
    }

    func clear() {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<UsageSnapshotRecord>())
            for record in records {
                context.delete(record)
            }
            try context.save()
            recent = []
        } catch {
            Self.logger.error("Clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Same-day lookup: fetch a window, then filter with `Calendar` (more reliable than exact predicate bounds).
    private func findRecords(on dayStart: Date, calendar: Calendar) -> [UsageSnapshotRecord] {
        guard let context else { return [] }
        let windowStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<UsageSnapshotRecord>(
            predicate: #Predicate { record in
                record.fetchedAt >= windowStart && record.fetchedAt < windowEnd
            },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.filter { calendar.isDate($0.fetchedAt, inSameDayAs: dayStart) }
    }

    private func reload() {
        guard let context else { return }
        var descriptor = FetchDescriptor<UsageSnapshotRecord>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let records = (try? context.fetch(descriptor)) ?? []
        recent = records.map { $0.toSnapshot() }
    }

    private func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            Self.logger.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
