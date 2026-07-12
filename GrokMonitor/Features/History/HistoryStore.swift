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

        if !fm.fileExists(atPath: storeURL.path) {
            let legacyCandidates = [
                base.appendingPathComponent("GrokUsage/history.store"),
                base.appendingPathComponent("default.store"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(
                        "Library/Containers/com.grokusage.app/Data/Library/Application Support/default.store"
                    )
            ]
            for legacy in legacyCandidates {
                guard fm.fileExists(atPath: legacy.path) else { continue }
                try? fm.copyItem(at: legacy, to: storeURL)
                // Also copy sidecar files SwiftData may use.
                for suffix in ["-shm", "-wal"] {
                    let side = URL(fileURLWithPath: legacy.path + suffix)
                    let dest = URL(fileURLWithPath: storeURL.path + suffix)
                    if fm.fileExists(atPath: side.path), !fm.fileExists(atPath: dest.path) {
                        try? fm.copyItem(at: side, to: dest)
                    }
                }
                break
            }
        }
        return storeURL
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

        if let existing = findRecord(on: dayStart, calendar: cal) {
            existing.apply(snapshot)
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

    private func findRecord(on dayStart: Date, calendar: Calendar) -> UsageSnapshotRecord? {
        guard let context else { return nil }
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var descriptor = FetchDescriptor<UsageSnapshotRecord>(
            predicate: #Predicate { record in
                record.fetchedAt >= dayStart && record.fetchedAt < end
            },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
