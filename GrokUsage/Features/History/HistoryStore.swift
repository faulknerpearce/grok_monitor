import Foundation
import Combine
import SwiftData

@Model
final class UsageSnapshotRecord {
    @Attribute(.unique) var id: UUID
    var fetchedAt: Date
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var productsJSON: Data
    var extraCredits: Double?
    var accountEmail: String?
    var rawPayload: Data?

    init(from snapshot: WeeklyUsageSnapshot) {
        self.id = snapshot.id
        self.fetchedAt = snapshot.fetchedAt
        self.usedPercent = snapshot.usedPercent
        self.remainingPercent = snapshot.remainingPercent
        self.resetsAt = snapshot.resetsAt
        self.productsJSON = (try? JSONEncoder().encode(snapshot.products)) ?? Data()
        self.extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        self.accountEmail = snapshot.accountEmail
        self.rawPayload = snapshot.rawPayload
    }

    func apply(_ snapshot: WeeklyUsageSnapshot) {
        fetchedAt = snapshot.fetchedAt
        usedPercent = snapshot.usedPercent
        remainingPercent = snapshot.remainingPercent
        resetsAt = snapshot.resetsAt
        productsJSON = (try? JSONEncoder().encode(snapshot.products)) ?? Data()
        extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        accountEmail = snapshot.accountEmail
        rawPayload = snapshot.rawPayload
    }

    func toSnapshot() -> WeeklyUsageSnapshot {
        let products = (try? JSONDecoder().decode([ProductUsage].self, from: productsJSON)) ?? []
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
    private var container: ModelContainer?
    private var context: ModelContext?

    @Published private(set) var recent: [WeeklyUsageSnapshot] = []

    init(inMemory: Bool = false) {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            let container = try ModelContainer(for: UsageSnapshotRecord.self, configurations: config)
            self.container = container
            self.context = ModelContext(container)
            reload()
        } catch {
            assertionFailure("SwiftData failed: \(error)")
        }
    }

    /// Keeps one end-of-day snapshot per calendar day (updates same-day row).
    /// Skips only near-identical samples within 60s on the **same** day.
    func append(_ snapshot: WeeklyUsageSnapshot) {
        guard let context else { return }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: snapshot.fetchedAt)

        // Same-day near-duplicate within 60s — skip.
        if let last = recent.first,
           cal.isDate(last.fetchedAt, inSameDayAs: snapshot.fetchedAt),
           abs(last.usedPercent - snapshot.usedPercent) < 0.05,
           abs(last.fetchedAt.timeIntervalSince(snapshot.fetchedAt)) < 60
        {
            return
        }

        // Update existing record for this calendar day if present.
        if let existing = findRecord(on: dayStart, calendar: cal) {
            existing.apply(snapshot)
            try? context.save()
            reload()
            return
        }

        context.insert(UsageSnapshotRecord(from: snapshot))
        try? context.save()
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
            // ignore
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
}
