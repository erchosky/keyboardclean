import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Ajustes persistidos: duración, apariencia, sonido e idioma.
final class SettingsTests: XCTestCase {
    func testCleaningDurationClampsTimedValues() {
        XCTAssertEqual(CleaningDuration.timed(seconds: 1).timedSeconds, 10)
        XCTAssertEqual(CleaningDuration.timed(seconds: 60).timedSeconds, 60)
        XCTAssertEqual(CleaningDuration.timed(seconds: 9_999).timedSeconds, 1_800)
        XCTAssertEqual(CleaningDuration.timed(seconds: .nan).timedSeconds, CleaningDuration.defaultSeconds)
        XCTAssertEqual(CleaningDuration.timed(seconds: .infinity).timedSeconds, CleaningDuration.maximumTimedSeconds)
        XCTAssertEqual(CleaningDuration.timed(seconds: -.infinity).timedSeconds, CleaningDuration.minimumSeconds)
        XCTAssertNil(CleaningDuration.infinite.timedSeconds)
    }

    func testAppSettingsClampDuration() {
        XCTAssertEqual(AppSettings.clampDuration(1), 10)
        XCTAssertEqual(AppSettings.clampDuration(600), 600)
        XCTAssertEqual(AppSettings.clampDuration(9_999), 1_800)
        XCTAssertEqual(AppSettings.clampDuration(.nan), CleaningDuration.defaultSeconds)
        XCTAssertEqual(AppSettings.clampDuration(.infinity), CleaningDuration.maximumTimedSeconds)
        XCTAssertEqual(AppSettings.clampDuration(-.infinity), CleaningDuration.minimumSeconds)
    }

    @MainActor
    func testCustomDurationPublishesOnlyNormalizedValue() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var publicationCount = 0
        let cancellable = settings.objectWillChange.sink {
            publicationCount += 1
        }

        settings.customDurationSeconds = 1

        XCTAssertEqual(settings.customDurationSeconds, CleaningDuration.minimumSeconds)
        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(cancellable) { }
    }

    @MainActor
    func testCustomDurationNormalizesAndPersistsFiniteValues() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cases: [(Double, Double)] = [
            (1, CleaningDuration.minimumSeconds),
            (75, 75),
            (9_999, CleaningDuration.maximumTimedSeconds),
            (.nan, CleaningDuration.defaultSeconds),
            (.infinity, CleaningDuration.maximumTimedSeconds),
            (-.infinity, CleaningDuration.minimumSeconds)
        ]

        for (input, expected) in cases {
            settings.customDurationSeconds = input
            XCTAssertEqual(settings.customDurationSeconds, expected)
            XCTAssertEqual(defaults.double(forKey: "customDurationSeconds"), expected)
        }
    }

    func testDurationPresetsAndCustomAvailability() {
        XCTAssertEqual(AppSettings.DurationMode.primaryCases, [.thirtySeconds, .sixtySeconds, .twoMinutes, .custom, .infinite])
        XCTAssertTrue(AppSettings.DurationMode.primaryCases.contains(.custom))
    }

    @MainActor
    func testManualAndCustomSelectedDurations() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.selectedDurationMode = .infinite
        XCTAssertNil(settings.selectedDuration.timedSeconds)

        settings.selectedDurationMode = .custom
        settings.customDurationSeconds = 75
        XCTAssertEqual(settings.selectedDuration.timedSeconds, 75)
    }

    @MainActor
    func testAppearancePersistsWithoutStandardDefaults() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.appearanceMode = .dark
        let restored = AppSettings(defaults: defaults)

        XCTAssertEqual(restored.appearanceMode, .dark)
        XCTAssertEqual(restored.appearanceMode.colorScheme, .dark)
    }

    @MainActor
    func testSoundPreferencePersists() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.soundEnabled = false

        XCTAssertFalse(AppSettings(defaults: defaults).soundEnabled)
    }

    @MainActor
    func testLanguagePreferencePersists() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.languageMode = .english
        XCTAssertEqual(AppSettings(defaults: defaults).languageMode, .english)

        settings.languageMode = .spanish
        XCTAssertEqual(AppSettings(defaults: defaults).languageMode, .spanish)

        settings.languageMode = .automatic
        XCTAssertEqual(AppSettings(defaults: defaults).languageMode, .automatic)
    }

    @MainActor
    func testOneHundredLanguageChangesRemainValidAndPersisted() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let languages: [AppSettings.LanguageMode] = [.automatic, .spanish, .english]

        for index in 0..<100 {
            let language = languages[index % languages.count]
            settings.languageMode = language
            XCTAssertEqual(AppSettings(defaults: defaults).languageMode, language)
            XCTAssertNotEqual(AppText.string("main.start", language: language), "main.start")
        }
    }
}
