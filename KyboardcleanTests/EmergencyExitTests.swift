import CoreGraphics
import XCTest
@testable import Kyboardclean

/// Atajos de salida: Control + Option + Command + Escape y Escape 5 veces en 3 segundos.
final class EmergencyExitTests: XCTestCase {
    private let escape = EmergencyKeyClassifier.escapeKeyCode

    func testEmergencyShortcutRequiresControlOptionAndCommand() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: escape, flags: flags), .emergencyStop)
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: escape, flags: flags.union(.maskShift)), .emergencyStop)
    }

    func testSystemForceQuitIsRecognisedSoItCanPassThrough() {
        XCTAssertEqual(
            EmergencyKeyClassifier.classify(keyCode: escape, flags: [.maskAlternate, .maskCommand]),
            .systemForceQuit
        )
    }

    func testOtherEscapeCombinationsCountForTheSequence() {
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: escape, flags: []), .escape)
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: escape, flags: [.maskControl]), .escape)
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: escape, flags: [.maskCommand]), .escape)
    }

    func testNonEscapeKeysAreIgnored() {
        let allModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        XCTAssertEqual(EmergencyKeyClassifier.classify(keyCode: 0, flags: allModifiers), .other)
    }

    func testFivePressesWithinThreeSecondsTriggerAndReset() {
        var detector = EscapeSequenceDetector()
        let second: UInt64 = 1_000_000_000
        for press in 0..<4 {
            XCTAssertFalse(detector.register(atUptimeNanoseconds: UInt64(press) * second / 2))
        }
        XCTAssertTrue(detector.register(atUptimeNanoseconds: 2 * second))
        XCTAssertFalse(detector.register(atUptimeNanoseconds: 2 * second + 1), "Tras disparar, la secuencia empieza de cero")
    }

    func testPressesOutsideTheWindowDoNotCount() {
        var detector = EscapeSequenceDetector()
        let second: UInt64 = 1_000_000_000
        for press in 0..<5 {
            XCTAssertFalse(detector.register(atUptimeNanoseconds: UInt64(press) * 2 * second))
        }
    }

    func testResetClearsPendingPresses() {
        var detector = EscapeSequenceDetector()
        for press in 0..<4 {
            _ = detector.register(atUptimeNanoseconds: UInt64(press))
        }
        detector.reset()
        XCTAssertFalse(detector.register(atUptimeNanoseconds: 10))
    }
}
