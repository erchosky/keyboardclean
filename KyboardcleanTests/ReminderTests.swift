import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Recordatorios locales y permisos de notificaciones.
final class ReminderTests: XCTestCase {
    func testReminderFrequencyIntervals() {
        XCTAssertNil(ReminderFrequency.never.interval)
        XCTAssertEqual(ReminderFrequency.weekly.interval, 604_800)
        XCTAssertEqual(ReminderFrequency.everyTwoWeeks.interval, 1_209_600)
        XCTAssertEqual(ReminderFrequency.monthly.interval, 2_592_000)
    }

    @MainActor
    func testReminderSchedulesAndPersistsWhenAuthorized() async {
        let suiteName = "KyboardcleanReminderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduledFrequency = LockedValue<ReminderFrequency?>(nil)
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { frequency, _, _ in scheduledFrequency.set(frequency) },
            cancelOperation: { }
        )

        await manager.setFrequency(.weekly, language: .english)

        XCTAssertEqual(manager.frequency, .weekly)
        XCTAssertEqual(manager.authorizationState, .allowed)
        XCTAssertTrue(manager.isScheduleActive)
        XCTAssertEqual(scheduledFrequency.value, .weekly)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.weekly.rawValue)
    }

    @MainActor
    func testReminderFrequencyChangesReplacePendingRequestAndDisableCleanly() async {
        let suiteName = "KyboardcleanReminderReplacementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scheduled = LockedArray<ReminderFrequency>()
        let cancellations = LockedCounter()
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { frequency, _, _ in scheduled.append(frequency) },
            cancelOperation: { cancellations.increment() }
        )

        await manager.setFrequency(.weekly, language: .english)
        await manager.setFrequency(.everyTwoWeeks, language: .english)
        await manager.setFrequency(.monthly, language: .spanish)

        XCTAssertEqual(scheduled.values, [.weekly, .everyTwoWeeks, .monthly])
        XCTAssertEqual(cancellations.value, 3)
        XCTAssertEqual(manager.frequency, .monthly)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.monthly.rawValue)

        await manager.setFrequency(.never, language: .spanish)
        XCTAssertEqual(cancellations.value, 4)
        XCTAssertEqual(manager.frequency, .never)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.never.rawValue)
    }

    @MainActor
    func testReminderSchedulingFailureCannotLeaveOldScheduleShownAsActive() async {
        let suiteName = "KyboardcleanReminderFailureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ReminderFrequency.weekly.rawValue, forKey: "reminderFrequency")
        let cancellations = LockedCounter()
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { _, _, _ in throw CocoaError(.fileWriteUnknown) },
            cancelOperation: { cancellations.increment() }
        )

        await manager.setFrequency(.monthly, language: .english)

        XCTAssertEqual(cancellations.value, 1)
        XCTAssertEqual(manager.frequency, .monthly)
        XCTAssertEqual(manager.authorizationState, .unavailable)
        XCTAssertFalse(manager.isScheduleActive)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.monthly.rawValue)
    }

    @MainActor
    func testReminderDisableWaitsForInFlightScheduleThenCancelsIt() async {
        let suiteName = "KyboardcleanReminderRaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gate = AsyncGate()
        let pendingFrequency = LockedValue<ReminderFrequency?>(nil)
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { frequency, _, _ in
                await gate.wait()
                pendingFrequency.set(frequency)
            },
            cancelOperation: { pendingFrequency.set(nil) }
        )

        let scheduleTask = Task {
            await manager.setFrequency(.weekly, language: .english)
        }
        while await gate.waiterCount == 0 {
            await Task.yield()
        }
        let releaseTask = Task {
            try? await Task.sleep(for: .milliseconds(20))
            await gate.open()
        }

        await manager.setFrequency(.never, language: .english)
        await scheduleTask.value
        await releaseTask.value

        XCTAssertNil(pendingFrequency.value)
        XCTAssertEqual(manager.frequency, .never)
    }

    @MainActor
    func testReminderNotificationContentFollowsSelectedLanguage() async {
        let suiteName = "KyboardcleanReminderLocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let content = LockedArray<String>()
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { _, title, body in content.append("\(title)|\(body)") },
            cancelOperation: { }
        )

        await manager.setFrequency(.weekly, language: .english)
        await manager.setFrequency(.weekly, language: .spanish)

        XCTAssertEqual(content.values.count, 2)
        XCTAssertNotEqual(content.values[0], content.values[1])
        XCTAssertTrue(content.values[0].contains(AppText.string("reminder.notification.title", language: .english)))
        XCTAssertTrue(content.values[1].contains(AppText.string("reminder.notification.title", language: .spanish)))
    }

    func testNativeNotificationCenterNeverContainsDuplicateReminderRequests() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let kyboardcleanRequests = requests.filter {
            $0.identifier == ReminderManager.requestIdentifier
        }

        XCTAssertLessThanOrEqual(kyboardcleanRequests.count, 1)
    }

    @MainActor
    func testReminderKeepsDesiredFrequencyWhenDenied() async {
        let suiteName = "KyboardcleanReminderDeniedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cancellationCount = LockedCounter()
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { false },
            scheduleOperation: { _, _, _ in XCTFail("Denied reminders must not be scheduled") },
            cancelOperation: { cancellationCount.increment() }
        )

        await manager.setFrequency(.monthly, language: .spanish)

        XCTAssertEqual(manager.frequency, .monthly)
        XCTAssertEqual(manager.authorizationState, .denied)
        XCTAssertFalse(manager.isScheduleActive)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.monthly.rawValue)
        XCTAssertEqual(cancellationCount.value, 1)
    }

    @MainActor
    func testReminderDeniedPreferenceSurvivesRestartAndRecoversAuthorization() async {
        let suiteName = "KyboardcleanReminderRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let permission = LockedValue(false)
        let pending = LockedValue<ReminderFrequency?>(nil)

        let deniedManager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { permission.value },
            scheduleOperation: { frequency, _, _ in pending.set(frequency) },
            cancelOperation: { pending.set(nil) }
        )
        await deniedManager.setFrequency(.weekly, language: .english)
        XCTAssertEqual(deniedManager.frequency, .weekly)
        XCTAssertFalse(deniedManager.isScheduleActive)

        permission.set(true)
        let restoredManager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { permission.value },
            scheduleOperation: { frequency, _, _ in pending.set(frequency) },
            cancelOperation: { pending.set(nil) }
        )
        await restoredManager.setFrequency(restoredManager.frequency, language: .spanish)

        XCTAssertEqual(restoredManager.frequency, .weekly)
        XCTAssertEqual(restoredManager.authorizationState, .allowed)
        XCTAssertTrue(restoredManager.isScheduleActive)
        XCTAssertEqual(pending.value, .weekly)
    }

    @MainActor
    func testReminderLanguageRefreshNeverDestroysDeniedDesiredFrequency() async {
        let suiteName = "KyboardcleanReminderDeniedLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { false },
            scheduleOperation: { _, _, _ in XCTFail("Denied reminders must not be scheduled") },
            cancelOperation: { }
        )

        for frequency in [ReminderFrequency.weekly, .everyTwoWeeks, .monthly] {
            await manager.setFrequency(frequency, language: .english)
            await manager.setFrequency(frequency, language: .spanish)
            XCTAssertEqual(manager.frequency, frequency)
            XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), frequency.rawValue)
            XCTAssertFalse(manager.isScheduleActive)
        }

        await manager.setFrequency(.never, language: .automatic)
        XCTAssertEqual(manager.frequency, .never)
    }

    @MainActor
    func testOneHundredReminderChangesKeepOnlyLatestFrequency() async {
        let suiteName = "KyboardcleanReminderStressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let pending = LockedValue<ReminderFrequency?>(nil)
        let manager = ReminderManager(
            defaults: defaults,
            authorizationProvider: { true },
            scheduleOperation: { frequency, _, _ in pending.set(frequency) },
            cancelOperation: { pending.set(nil) }
        )
        let frequencies = ReminderFrequency.allCases

        for index in 0..<100 {
            await manager.setFrequency(frequencies[index % frequencies.count], language: .english)
        }

        XCTAssertEqual(manager.frequency, .monthly)
        XCTAssertEqual(pending.value, .monthly)
        XCTAssertEqual(defaults.string(forKey: "reminderFrequency"), ReminderFrequency.monthly.rawValue)
    }
}
