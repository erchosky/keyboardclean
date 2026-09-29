import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Historial local de sesiones: límites, datos corruptos y estadísticas.
final class CleaningHistoryTests: XCTestCase {
    @MainActor
    func testCleaningHistoryPersistsStatisticsAndClear() {
        let suiteName = "KyboardcleanHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleaningHistoryStore(defaults: defaults)
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)

        store.record(date: olderDate, durationSeconds: 30, outcome: .cancelled)
        store.record(date: newerDate, durationSeconds: 90, outcome: .completed)

        XCTAssertEqual(store.entries.map(\.date), [newerDate, olderDate])
        XCTAssertEqual(store.statistics.cleaningCount, 1)
        XCTAssertEqual(store.statistics.totalDurationSeconds, 90)
        XCTAssertEqual(store.statistics.averageDurationSeconds, 90)
        XCTAssertEqual(store.statistics.lastCleaningDate, newerDate)
        XCTAssertEqual(CleaningHistoryStore(defaults: defaults).entries, store.entries)

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(CleaningHistoryStore(defaults: defaults).entries.isEmpty)
    }

    @MainActor
    func testCleaningHistoryAppliesStorageLimit() {
        let suiteName = "KyboardcleanHistoryLimitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleaningHistoryStore(defaults: defaults, maximumEntryCount: 3)

        for index in 1...5 {
            store.record(
                date: Date(timeIntervalSince1970: Double(index)),
                durationSeconds: Double(index),
                outcome: .completed
            )
        }

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.map(\.durationSeconds), [5, 4, 3])
    }

    @MainActor
    func testCleaningHistoryRecoversFromCorruptStorage() {
        let suiteName = "KyboardcleanCorruptHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "cleaningHistory")

        let store = CleaningHistoryStore(defaults: defaults)
        XCTAssertTrue(store.entries.isEmpty)

        store.record(date: Date(timeIntervalSince1970: 100), durationSeconds: 30, outcome: .completed)
        XCTAssertEqual(CleaningHistoryStore(defaults: defaults).entries.count, 1)
    }

    @MainActor
    func testCleaningHistoryLoadsOlderUnsortedDataAndKeepsNewestEntries() throws {
        let suiteName = "KyboardcleanLegacyHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let entries = (1...5).map {
            CleaningHistoryEntry(
                id: UUID(),
                date: Date(timeIntervalSince1970: Double($0)),
                durationSeconds: Double($0),
                outcome: $0.isMultiple(of: 2) ? .cancelled : .completed
            )
        }
        defaults.set(try JSONEncoder().encode(entries), forKey: "cleaningHistory")

        let store = CleaningHistoryStore(defaults: defaults, maximumEntryCount: 3)
        XCTAssertEqual(store.entries.map(\.durationSeconds), [5, 4, 3])
    }

    @MainActor
    func testCleaningHistorySanitizesInvalidDurationsAndDuplicateIDs() throws {
        let suiteName = "KyboardcleanSanitizedHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let duplicateID = UUID()
        let entries = [
            CleaningHistoryEntry(id: duplicateID, date: Date(timeIntervalSince1970: 4), durationSeconds: 40, outcome: .completed),
            CleaningHistoryEntry(id: duplicateID, date: Date(timeIntervalSince1970: 3), durationSeconds: 30, outcome: .cancelled),
            CleaningHistoryEntry(id: UUID(), date: Date(timeIntervalSince1970: 2), durationSeconds: -20, outcome: .cancelled),
            CleaningHistoryEntry(id: UUID(), date: Date(timeIntervalSince1970: 1), durationSeconds: 99_999, outcome: .completed)
        ]
        defaults.set(try JSONEncoder().encode(entries), forKey: "cleaningHistory")

        let store = CleaningHistoryStore(defaults: defaults)

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.map(\.durationSeconds), [40, 0, CleaningDuration.hardSafetyLimitSeconds])
        XCTAssertEqual(Set(store.entries.map(\.id)).count, store.entries.count)

        store.record(date: Date(), durationSeconds: .nan, outcome: .completed)
        XCTAssertEqual(store.entries.count, 3)
    }

    @MainActor
    func testSessionHistoryRecordsOnlySessionsThatReachedActiveState() async {
        let suiteName = "KyboardcleanSessionHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleaningHistoryStore(defaults: defaults)
        let manager = CleaningSessionManager(testing: (), historyStore: store)
        let sessionDate = Date(timeIntervalSince1970: 1_000)

        manager._testMarkStarting(sessionID: 1)
        manager.stop(reason: .eventTapFailed)
        XCTAssertTrue(store.entries.isEmpty)

        manager._testMarkActive(sessionID: 2, remaining: 30, total: 30)
        manager._testSetSessionStart(monotonic: monotonicTime(secondsAgo: 5), date: sessionDate)
        manager.stop(reason: .manual)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].outcome, .cancelled)
        XCTAssertEqual(store.entries[0].date, sessionDate)
        XCTAssertEqual(store.entries[0].durationSeconds, 5, accuracy: 0.2)

        manager.stop(reason: .manual)
        XCTAssertEqual(store.entries.count, 1, "Idempotent stop must not duplicate history")

        manager._testMarkActive(sessionID: 3, remaining: 30, total: 30)
        manager._testSetSessionStart(monotonic: monotonicTime(secondsAgo: 2), date: sessionDate.addingTimeInterval(1))
        manager.stop(reason: .unsafeState)
        XCTAssertEqual(store.entries.first?.outcome, .cancelled)

        manager._testMarkActive(sessionID: 4, remaining: 30, total: 30)
        manager._testSetSessionStart(monotonic: monotonicTime(secondsAgo: 1), date: sessionDate.addingTimeInterval(2))
        manager.stop(reason: .appTerminated)
        XCTAssertEqual(store.entries.first?.outcome, .cancelled)

        manager._testMarkActive(sessionID: 5, remaining: 1, total: 30)
        manager._testSetSessionStart(monotonic: monotonicTime(secondsAgo: 3), date: sessionDate.addingTimeInterval(3))
        manager.stop(reason: .timerFinished)
        try? await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(store.entries.count, 4)
        XCTAssertEqual(store.entries.first?.outcome, .completed)
        XCTAssertEqual(store.entries.first?.durationSeconds ?? 0, 3, accuracy: 0.2)
        XCTAssertEqual(store.statistics.cleaningCount, 1)
        XCTAssertEqual(store.statistics.lastCleaningDate, sessionDate.addingTimeInterval(3))
        XCTAssertEqual(store.statistics.totalDurationSeconds, 3, accuracy: 0.2)
        XCTAssertEqual(store.statistics.averageDurationSeconds, 3, accuracy: 0.2)
        manager._testResetToIdle()
    }

    @MainActor
    func testOneThousandHistoryWritesRemainBoundedAndClearRepeatedly() {
        let suiteName = "KyboardcleanHistoryStressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CleaningHistoryStore(defaults: defaults)

        for index in 0..<1_000 {
            store.record(
                date: Date(timeIntervalSince1970: Double(index)),
                durationSeconds: Double(index % 1_801),
                outcome: index.isMultiple(of: 2) ? .completed : .cancelled
            )
        }
        XCTAssertEqual(store.entries.count, 500)
        XCTAssertEqual(Set(store.entries.map(\.id)).count, 500)

        for _ in 0..<100 {
            store.clear()
        }
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(CleaningHistoryStore(defaults: defaults).entries.isEmpty)
    }
}
