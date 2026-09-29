import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Ciclo de vida del CGEventTap: arranque, parada, generaciones y reactivación.
final class EventTapTests: XCTestCase {
    @MainActor
    func testEventTapStartReturnsAsynchronously() async {
        let completionExpectation = expectation(description: "async start completion")
        let manager = EventTapManager { _, _ in
            Thread.sleep(forTimeInterval: 0.05)
            return true
        }
        let startedAt = DispatchTime.now()

        manager.start(sessionID: 1, hardSafetyDeadline: .now() + .seconds(1)) { result in
            XCTAssertTrue(result)
            completionExpectation.fulfill()
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000_000
        XCTAssertLessThan(elapsed, 0.02)
        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    func testEventTapStartReportsDelayedFailure() async {
        let completionExpectation = expectation(description: "failed start completion")
        let manager = EventTapManager { _, _ in
            Thread.sleep(forTimeInterval: 0.03)
            return false
        }

        manager.start(sessionID: 1, hardSafetyDeadline: .now() + .seconds(1)) { result in
            XCTAssertFalse(result)
            completionExpectation.fulfill()
        }

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    func testStopDuringEventTapStartCancelsResult() async {
        let completionExpectation = expectation(description: "cancelled start completion")
        let manager = EventTapManager { _, _ in
            Thread.sleep(forTimeInterval: 0.05)
            return true
        }

        manager.start(sessionID: 1, hardSafetyDeadline: .now() + .seconds(1)) { result in
            XCTAssertFalse(result)
            completionExpectation.fulfill()
        }
        manager.stop()
        manager.stop()

        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    func testConcurrentEventTapStopsAreIdempotent() {
        let manager = EventTapManager()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            manager.stop()
        }

        XCTAssertFalse(manager.isRunning)
        XCTAssertTrue(manager.isDisarmedForExit)
    }

    @MainActor
    func testOneThousandImmediateEventTapStartStopCyclesComplete() async {
        let completions = expectation(description: "all rapid start callbacks")
        completions.expectedFulfillmentCount = 1_000
        let manager = EventTapManager { _, _ in true }

        for sessionID in 1...1_000 {
            manager.start(
                sessionID: UInt64(sessionID),
                hardSafetyDeadline: .now() + .seconds(1)
            ) { _ in
                completions.fulfill()
            }
            manager.stop()
        }

        await fulfillment(of: [completions], timeout: 5)
        XCTAssertFalse(manager.isRunning)
        XCTAssertTrue(manager.isDisarmedForExit)
    }

    @MainActor
    func testConcurrentEventTapStartsDoNotLeaveManagerRunning() async {
        let completions = expectation(description: "all concurrent start callbacks")
        completions.expectedFulfillmentCount = 100
        let manager = EventTapManager { _, _ in false }

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            manager.start(
                sessionID: UInt64(index + 1),
                hardSafetyDeadline: .now() + .seconds(1)
            ) { _ in
                completions.fulfill()
            }
        }
        manager.stop()

        await fulfillment(of: [completions], timeout: 5)
        XCTAssertFalse(manager.isRunning)
        XCTAssertTrue(manager.isDisarmedForExit)
    }

    @MainActor
    func testStopDoesNotWaitForSlowStartupOperation() async {
        let completionExpectation = expectation(description: "cancelled slow start")
        let manager = EventTapManager { _, _ in
            Thread.sleep(forTimeInterval: 0.2)
            return true
        }

        manager.start(sessionID: 1, hardSafetyDeadline: .now() + .seconds(1)) { result in
            XCTAssertFalse(result)
            completionExpectation.fulfill()
        }

        let startedAt = DispatchTime.now()
        manager.stop()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000_000

        XCTAssertLessThan(elapsed, 0.02)
        await fulfillment(of: [completionExpectation], timeout: 1)
    }

    @MainActor
    func testRapidStartStopStartKeepsOnlyNewestResult() async {
        let completions = expectation(description: "both start completions")
        completions.expectedFulfillmentCount = 2
        var results: [UInt64: Bool] = [:]
        let manager = EventTapManager { sessionID, _ in
            if sessionID == 1 {
                Thread.sleep(forTimeInterval: 0.04)
            }
            return true
        }

        manager.start(sessionID: 1, hardSafetyDeadline: .now() + .seconds(1)) { result in
            results[1] = result
            completions.fulfill()
        }
        manager.stop()
        manager.start(sessionID: 2, hardSafetyDeadline: .now() + .seconds(1)) { result in
            results[2] = result
            completions.fulfill()
        }

        await fulfillment(of: [completions], timeout: 1)
        XCTAssertEqual(results[1], false)
        XCTAssertEqual(results[2], true)
    }

    func testEventTapRejectsStaleSessionGeneration() {
        let manager = EventTapManager()
        manager._testSetActiveSessionID(2)

        XCTAssertFalse(manager._testDisarm(sessionID: 1))
        XCTAssertTrue(manager._testDisarm(sessionID: 2))

        manager.stop()
    }

    func testTapThreadCompletionWakesEveryWaiter() {
        let completion = TapThreadCompletion()
        let waiters = DispatchGroup()
        let completedWaiters = LockedCounter()

        for _ in 0..<8 {
            waiters.enter()
            DispatchQueue.global().async {
                if completion.wait(timeout: .now() + 1) {
                    completedWaiters.increment()
                }
                waiters.leave()
            }
        }

        completion.complete()
        completion.complete()

        XCTAssertEqual(waiters.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(completedWaiters.value, 8)
    }

    func testTapThreadCompletionTimesOutWhenThreadDoesNotFinish() {
        let completion = TapThreadCompletion()

        XCTAssertFalse(completion.wait(timeout: .now() + .milliseconds(10)))
        completion.complete()
        XCTAssertTrue(completion.wait(timeout: .now() + .milliseconds(10)))
    }

    func testOneThousandEventTapGenerationsRejectStaleCallbacks() {
        let manager = EventTapManager()

        for sessionID in 1...1_000 {
            manager._testSetActiveSessionID(UInt64(sessionID))
            XCTAssertFalse(manager._testDisarm(sessionID: UInt64(sessionID + 1)))
            XCTAssertTrue(manager._testDisarm(sessionID: UInt64(sessionID)))
            manager.stop()
        }
    }

    func testOneThousandReactivationCyclesNeverExceedRetryLimit() {
        var policy = TapReactivationAttemptPolicy()

        for _ in 0..<1_000 {
            XCTAssertEqual(policy.nextAttempt(), 1)
            XCTAssertEqual(policy.nextAttempt(), 2)
            XCTAssertEqual(policy.nextAttempt(), 3)
            XCTAssertNil(policy.nextAttempt())
            policy.reset()
        }
    }

    func testReactivationPolicyAllowsExactlyThreeAttemptsAndCanReset() {
        var policy = TapReactivationAttemptPolicy()
        XCTAssertEqual(policy.nextAttempt(), 1)
        XCTAssertEqual(policy.nextAttempt(), 2)
        XCTAssertEqual(policy.nextAttempt(), 3)
        XCTAssertNil(policy.nextAttempt())
        XCTAssertTrue(policy.isExhausted)
        policy.reset()
        XCTAssertEqual(policy.nextAttempt(), 1)
    }

    @MainActor
    func testEventTapCanDisarmWhileMainActorIsTemporarilyBlocked() {
        let manager = EventTapManager()
        manager._testSetActiveSessionID(9)
        let stopped = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            manager.stop()
            stopped.signal()
        }

        XCTAssertEqual(stopped.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(manager.runtimeState, .disarmedForExit)
    }
}
