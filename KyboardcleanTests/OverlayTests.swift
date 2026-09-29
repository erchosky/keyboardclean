import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Validación y fases visuales del overlay de limpieza.
final class OverlayTests: XCTestCase {
    func testOverlayStructuralValidationAllowsFrameTolerance() {
        let requiredBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces.rawValue
            | NSWindow.CollectionBehavior.fullScreenAuxiliary.rawValue
        let window = overlaySnapshot(
            frame: CGRect(x: 0.5, y: -0.5, width: 1440.5, height: 900.5),
            collectionBehavior: requiredBehavior
        )

        XCTAssertTrue(
            OverlayValidation.isStructurallyValid(
                screenFrames: [CGRect(x: 0, y: 0, width: 1440, height: 900)],
                windows: [window],
                requiredLevel: NSWindow.Level.screenSaver.rawValue,
                requiredCollectionBehavior: requiredBehavior
            )
        )
    }

    func testOverlayStructuralValidationRejectsMissingScreenWindow() {
        XCTAssertFalse(
            OverlayValidation.isStructurallyValid(
                screenFrames: [
                    CGRect(x: 0, y: 0, width: 1440, height: 900),
                    CGRect(x: 1440, y: 0, width: 1920, height: 1080)
                ],
                windows: [overlaySnapshot()],
                requiredLevel: NSWindow.Level.screenSaver.rawValue,
                requiredCollectionBehavior: 0
            )
        )
    }

    func testOverlayVisualValidationRecoversAfterTransientFailure() {
        var tracker = OverlayVisualValidationTracker(failureLimit: 3)

        XCTAssertEqual(tracker.record(isValid: false), .retry)
        XCTAssertEqual(tracker.record(isValid: true), .valid)
        XCTAssertEqual(tracker.consecutiveFailures, 0)
        XCTAssertEqual(tracker.record(isValid: false), .retry)
    }

    func testOverlayStartupGraceIsFourHundredMilliseconds() {
        XCTAssertEqual(OverlayValidation.startupRetryDelaysMilliseconds.reduce(0, +), 400)
        XCTAssertEqual(OverlayValidation.startupRetryDelaysMilliseconds.count, 3)
    }

    func testOverlayVisualValidationFailsAfterConsecutiveFailures() {
        var tracker = OverlayVisualValidationTracker(failureLimit: 3)

        XCTAssertEqual(tracker.record(isValid: false), .retry)
        XCTAssertEqual(tracker.record(isValid: false), .retry)
        XCTAssertEqual(tracker.record(isValid: false), .fail)
    }

    func testOverlayVisualValidationRejectsHiddenWindow() {
        let visible = overlaySnapshot()
        let hidden = overlaySnapshot(isVisible: false)

        XCTAssertTrue(
            OverlayValidation.isVisuallyValid(
                screenFrames: [visible.frame],
                windows: [visible]
            )
        )
        XCTAssertFalse(
            OverlayValidation.isVisuallyValid(
                screenFrames: [hidden.frame],
                windows: [hidden]
            )
        )
    }

    @MainActor
    func testStaleScreenConfigurationCallbackIsIgnored() {
        let controller = OverlayWindowController()
        var callbackCount = 0
        controller.onOverlayUnavailable = { callbackCount += 1 }
        controller._testSetPresentation(generation: 2, isPresenting: true)

        controller._testHandleScreenConfigurationChange(generation: 1)
        XCTAssertEqual(callbackCount, 0)

        controller._testHandleScreenConfigurationChange(generation: 2)
        XCTAssertEqual(callbackCount, 1)
    }

    func testOverlayVisualPhasesOnlyCompleteForNormalTimerFinish() {
        XCTAssertEqual(OverlayVisualPhase(state: .starting), .preparing)
        XCTAssertEqual(OverlayVisualPhase(state: .active), .active)
        XCTAssertEqual(OverlayVisualPhase(state: .stopping(reason: .timerFinished)), .completed)
        XCTAssertEqual(OverlayVisualPhase(state: .stopping(reason: .manual)), .active)
        XCTAssertEqual(OverlayVisualPhase(state: .stopping(reason: .unsafeState)), .active)
    }

    func testOverlayCompletionUsesOpacityWithReduceMotion() {
        XCTAssertTrue(OverlayVisualPhase.usesDrawnCheck(reduceMotion: false))
        XCTAssertFalse(OverlayVisualPhase.usesDrawnCheck(reduceMotion: true))
    }
}
