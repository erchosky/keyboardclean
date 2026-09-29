import Foundation

struct CleaningHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case completed
        case cancelled
    }

    let id: UUID
    let date: Date
    let durationSeconds: TimeInterval
    let outcome: Outcome
}

struct CleaningStatistics: Equatable, Sendable {
    let cleaningCount: Int
    let totalDurationSeconds: TimeInterval
    let lastCleaningDate: Date?
    let averageDurationSeconds: TimeInterval
}

@MainActor
final class CleaningHistoryStore: ObservableObject {
    static let shared = CleaningHistoryStore()

    @Published private(set) var entries: [CleaningHistoryEntry]

    private enum Keys {
        static let entries = "cleaningHistory"
    }

    private let defaults: UserDefaults
    private let maximumEntryCount: Int

    private static let maximumRecordedDuration = CleaningDuration.hardSafetyLimitSeconds

    init(defaults: UserDefaults = .standard, maximumEntryCount: Int = 500) {
        self.defaults = defaults
        self.maximumEntryCount = max(1, maximumEntryCount)

        if let data = defaults.data(forKey: Keys.entries),
           let savedEntries = try? JSONDecoder().decode([CleaningHistoryEntry].self, from: data) {
            var seenIDs = Set<UUID>()
            entries = Array(
                savedEntries
                    .sorted { $0.date > $1.date }
                    .compactMap { entry in
                        guard seenIDs.insert(entry.id).inserted,
                              entry.durationSeconds.isFinite else {
                            return nil
                        }
                        return CleaningHistoryEntry(
                            id: entry.id,
                            date: entry.date,
                            durationSeconds: Self.normalizedDuration(entry.durationSeconds),
                            outcome: entry.outcome
                        )
                    }
                    .prefix(self.maximumEntryCount)
            )
        } else {
            entries = []
        }
    }

    var statistics: CleaningStatistics {
        let completedEntries = entries.filter { $0.outcome == .completed }
        let total = completedEntries.reduce(0) { $0 + $1.durationSeconds }
        return CleaningStatistics(
            cleaningCount: completedEntries.count,
            totalDurationSeconds: total,
            lastCleaningDate: completedEntries.first?.date,
            averageDurationSeconds: completedEntries.isEmpty ? 0 : total / Double(completedEntries.count)
        )
    }

    func record(date: Date, durationSeconds: TimeInterval, outcome: CleaningHistoryEntry.Outcome) {
        guard durationSeconds.isFinite else { return }
        let entry = CleaningHistoryEntry(
            id: UUID(),
            date: date,
            durationSeconds: Self.normalizedDuration(durationSeconds),
            outcome: outcome
        )
        entries.insert(entry, at: 0)
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        defaults.removeObject(forKey: Keys.entries)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: Keys.entries)
    }

    private static func normalizedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(max(0, duration), maximumRecordedDuration)
    }
}
