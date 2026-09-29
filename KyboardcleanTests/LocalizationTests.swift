import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Localización español/inglés: paridad de claves, placeholders y resolución.
final class LocalizationTests: XCTestCase {
    func testLocalizationFilesHaveParityWithoutDuplicatesOrEmptyValues() throws {
        let spanish = try localizationSource(language: "es")
        let english = try localizationSource(language: "en")

        XCTAssertEqual(spanish.duplicates, [])
        XCTAssertEqual(english.duplicates, [])
        XCTAssertEqual(spanish.values.count, 159)
        XCTAssertEqual(english.values.count, 159)
        XCTAssertEqual(Set(spanish.values.keys), Set(english.values.keys))
        XCTAssertFalse(spanish.values.values.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertFalse(english.values.values.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testLocalizationPlaceholdersMatchBetweenLanguages() throws {
        let spanish = try localizationSource(language: "es").values
        let english = try localizationSource(language: "en").values

        for key in spanish.keys.sorted() {
            XCTAssertEqual(
                placeholders(in: spanish[key] ?? ""),
                placeholders(in: english[key] ?? ""),
                "Placeholder mismatch for \(key)"
            )
        }
    }

    func testKnownLocalizationResolvesInSpanishAndEnglish() {
        XCTAssertEqual(AppText.string("main.start", language: .spanish), "Empezar limpieza")
        XCTAssertEqual(AppText.string("main.start", language: .english), "Start cleaning")
    }

    func testEveryLocalizationKeyResolvesWithoutExposingRawKey() throws {
        let keys = try localizationSource(language: "en").values.keys

        for language in [AppSettings.LanguageMode.spanish, .english] {
            for key in keys {
                XCTAssertNotEqual(AppText.string(key, language: language), key, "Raw key exposed: \(key)")
            }
        }
    }

    func testAutomaticLanguageUsesEnglishFallbackForUnsupportedSystemLanguage() {
        XCTAssertEqual(
            AppText.effectiveLanguage(for: .automatic, preferredLocalizations: ["fr"]),
            .english
        )
        XCTAssertEqual(
            AppText.effectiveLanguage(for: .automatic, preferredLocalizations: ["es-ES", "en"]),
            .spanish
        )
    }

    func testEffectiveLocaleMatchesSelectedLanguage() {
        XCTAssertEqual(AppText.locale(for: .spanish).language.languageCode?.identifier, "es")
        XCTAssertEqual(AppText.locale(for: .english).language.languageCode?.identifier, "en")
    }

    @MainActor
    func testOfflineLabelsContainSinglePercentSign() {
        for language in [AppSettings.LanguageMode.spanish, .english] {
            XCTAssertFalse(AppText.string("main.privacyNote", language: language).contains("%%"))
            XCTAssertFalse(AppText.string("settings.about.offline", language: language).contains("%%"))
        }
    }
}
