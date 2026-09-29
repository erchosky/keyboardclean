import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Sesión de limpieza: estados, temporizador, cancelaciones y errores.
final class CleaningSessionTests: XCTestCase {
    @MainActor
    func testRepeatedStartRequestsDoNotReplaceBusySession() {
        let manager = CleaningSessionManager(testing: ())

        manager._testMarkStarting(sessionID: 42)
        for _ in 0..<100 {
            manager.start(duration: .timed(seconds: 30), soundEnabled: false)
        }
        XCTAssertEqual(manager.state, .starting)
        XCTAssertEqual(manager._testCurrentSessionID, 42)

        manager._testMarkStopping(sessionID: 43)
        for _ in 0..<100 {
            manager.start(duration: .timed(seconds: 60), soundEnabled: false)
        }
        XCTAssertEqual(manager.state, .stopping(reason: .manual))
        XCTAssertEqual(manager._testCurrentSessionID, 43)
        manager._testResetToIdle()
    }

    func testCleaningStateBusyTransitions() {
        XCTAssertFalse(CleaningState.idle.isBusy)
        XCTAssertTrue(CleaningState.starting.isBusy)
        XCTAssertTrue(CleaningState.active.isBusy)
        XCTAssertTrue(CleaningState.stopping(reason: .manual).isBusy)
        XCTAssertTrue(CleaningState.stopping(reason: .manual).isStopping)
    }

    @MainActor
    func testOneThousandSessionStateStartStopCycles() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()

        for sessionID in 1...1_000 {
            manager._testMarkStarting(sessionID: UInt64(sessionID))
            XCTAssertTrue(manager.state.isBusy)
            manager.stop(reason: .manual)
            XCTAssertEqual(manager.state, .idle)
        }

        manager._testResetToIdle()
    }

    @MainActor
    func testCountdownPublishesOnlyWhenDisplayedSecondChanges() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()

        var publicationCount = 0
        let cancellable = manager.objectWillChange.sink {
            publicationCount += 1
        }

        for tick in 0..<240 {
            let elapsed = Double(tick) / 4
            manager._testPublishDisplayTimes(
                remaining: max(0, 60 - elapsed),
                hardLimit: max(0, 1_800 - elapsed)
            )
        }

        withExtendedLifetime(cancellable) { }
        XCTAssertEqual(publicationCount, 119)
        manager._testResetToIdle()
    }

    func testRequestedDurationUsesMonotonicDeadline() {
        let start = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        let deadline = CleaningSessionManager.deadline(after: 60, from: start)
        let halfway = DispatchTime(uptimeNanoseconds: 31_000_000_000)

        XCTAssertEqual(deadline.uptimeNanoseconds, 61_000_000_000)
        XCTAssertEqual(CleaningSessionManager.remainingSeconds(until: deadline, now: halfway), 30)
    }

    @MainActor
    func testRequestedDurationBeginsAtActiveConfirmationAfterSlowOrRetriedStart() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        let requestTime = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        let activeAfterSlowStart = requestTime + .seconds(8)

        for seconds in [30.0, 60.0, 75.0] {
            manager._testConfigureTiming(
                duration: .timed(seconds: seconds),
                activeAt: activeAfterSlowStart
            )
            XCTAssertEqual(
                manager._testRequestedDeadline?.uptimeNanoseconds,
                activeAfterSlowStart.uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
            )
        }

        let activeAfterRetry = requestTime + .seconds(12)
        manager._testConfigureTiming(duration: .timed(seconds: 30), activeAt: activeAfterRetry)
        XCTAssertEqual(
            manager._testRequestedDeadline?.uptimeNanoseconds,
            activeAfterRetry.uptimeNanoseconds + 30_000_000_000
        )
        manager._testResetToIdle()
    }

    @MainActor
    func testFailureBeforeActiveNeverCreatesRequestedDeadline() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkStarting(sessionID: 42)

        XCTAssertNil(manager._testRequestedDeadline)
        manager.stop(reason: .eventTapFailed)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager._testRequestedDeadline)
        XCTAssertEqual(manager.errorCode, .eventTapFailed)
        manager._testResetToIdle()
    }

    @MainActor
    func testSessionTickToleratesOnlyBoundedTapReactivation() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkActive(sessionID: 1, remaining: 30, total: 30)
        manager._testSetTapRuntimeState(
            .reactivating,
            sessionID: 1,
            reactivationDeadline: .now() + .seconds(2)
        )

        manager._testTick()
        XCTAssertEqual(manager.state, .active)

        manager._testSetTapRuntimeState(
            .reactivating,
            sessionID: 1,
            reactivationDeadline: .now() - .milliseconds(1)
        )
        manager._testTick()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.errorCode, .unsafeState)
        manager._testResetToIdle()
    }

    @MainActor
    func testCancellationDuringTapReactivationIsImmediateAndIdempotent() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkActive(sessionID: 7, remaining: 30, total: 30)
        manager._testSetTapRuntimeState(
            .reactivating,
            sessionID: 7,
            reactivationDeadline: .now() + .seconds(2)
        )

        manager.stop(reason: .manual)
        manager.stop(reason: .manual)
        XCTAssertEqual(manager.state, .idle)
        manager._testResetToIdle()
    }

    func testMaximumTimedDurationReportsTimerFinishedAtHardLimit() {
        XCTAssertEqual(
            CleaningSessionManager.hardLimitStopReason(for: .timed(seconds: 1_800)),
            .timerFinished
        )
        XCTAssertEqual(
            CleaningSessionManager.hardLimitStopReason(for: .infinite),
            .hardSafetyLimit
        )
    }

    @MainActor
    func testSessionIDRejectsStaleCallbacks() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()

        manager._testMarkStarting(sessionID: 1)
        XCTAssertTrue(manager.isCurrentSession(1))

        manager._testMarkStarting(sessionID: 2)
        XCTAssertFalse(manager.isCurrentSession(1))
        XCTAssertTrue(manager.isCurrentSession(2))

        manager._testResetToIdle()
        XCTAssertFalse(manager.isCurrentSession(2))
    }

    @MainActor
    func testStopIsIdempotent() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkStarting(sessionID: 1)

        manager.stop(reason: .manual)
        manager.stop(reason: .manual)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.errorCode)
    }

    @MainActor
    func testNormalTimerFinishKeepsOnlyTheVisualCompletionBriefly() async throws {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkActive(sessionID: 1, remaining: 1, total: 30)
        manager._testClearLifecycleEvents()

        manager.stop(reason: .timerFinished)

        XCTAssertEqual(manager.state, .stopping(reason: .timerFinished))
        XCTAssertEqual(manager.remainingSeconds, 0)
        XCTAssertEqual(manager.totalDurationSeconds, 30)
        XCTAssertEqual(manager._testLifecycleEvents, [])

        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.lastStopReason, .timerFinished)
        XCTAssertNil(manager.remainingSeconds)
        XCTAssertNil(manager.totalDurationSeconds)
        XCTAssertEqual(manager._testLifecycleEvents, ["eventTap.stop", "overlay.hide"])
        manager._testResetToIdle()
    }

    @MainActor
    func testUrgentStopInterruptsCompletionPresentationWithoutExposingInput() async throws {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkActive(sessionID: 2, remaining: 1, total: 30)
        manager._testClearLifecycleEvents()

        manager.stop(reason: .timerFinished)
        manager.stop(reason: .appTerminated)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.lastStopReason, .appTerminated)
        XCTAssertEqual(manager._testLifecycleEvents, ["eventTap.stop", "overlay.hide"])
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(manager._testLifecycleEvents, ["eventTap.stop", "overlay.hide"])
        manager._testResetToIdle()
    }

    @MainActor
    func testApplicationTerminationDuringStartingStopsSession() {
        let manager = CleaningSessionManager.shared
        manager._testResetToIdle()
        manager._testMarkStarting(sessionID: 1)

        AppDelegate().applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(manager.state, .idle)
        manager._testResetToIdle()
    }

    @MainActor
    func testOverlayUnavailableStopsAsError() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkStarting(sessionID: 1)

        manager.stop(reason: .overlayUnavailable)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.errorCode, .overlayUnavailable)
        XCTAssertNil(manager.lastStopReason)
    }

    @MainActor
    func testUnsafeStateMapsToUnsafeStateError() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testMarkStarting(sessionID: 1)

        manager.stop(reason: .unsafeState)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.errorCode, .unsafeState)
        manager._testResetToIdle()
    }

    @MainActor
    func testSecureEventInputBlocksStart() {
        let manager = CleaningSessionManager(testing: ())
        manager._testResetToIdle()
        manager._testSetSecureEventInputEnabled(true)

        manager.start(duration: .timed(seconds: 10), soundEnabled: false)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(
            manager.errorCode,
            .secureEventInput
        )

        manager._testResetToIdle()
    }
}
