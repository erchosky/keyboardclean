import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Recursos empaquetados, manifiesto de privacidad y permisos del sistema.
final class SystemIntegrationTests: XCTestCase {
    func testPrivacyManifestDeclaresRequiredReasonAPIs() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String])? in
            guard let category = entry["NSPrivacyAccessedAPIType"] as? String,
                  let values = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else {
                return nil
            }
            return (category, values)
        })

        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategorySystemBootTime"], ["35F9.1"])
    }

    func testBundledSoundEffectsHaveExpectedResources() throws {
        XCTAssertEqual(SoundEffect.activation.resourceName, "activation")
        XCTAssertEqual(SoundEffect.success.resourceName, "success")
        XCTAssertNotNil(Bundle.main.url(forResource: "NOTICE", withExtension: "txt", subdirectory: "Sounds"))

        // Los .wav no se publican en el repositorio (ver README): la prueba solo aplica si están instalados.
        let activation = Bundle.main.url(forResource: "activation", withExtension: "wav", subdirectory: "Sounds")
        let success = Bundle.main.url(forResource: "success", withExtension: "wav", subdirectory: "Sounds")
        try XCTSkipIf(activation == nil && success == nil, "Sonidos opcionales no instalados")
        XCTAssertNotNil(activation)
        XCTAssertNotNil(success)
    }

    @MainActor
    func testSoundManagerCachesLoadAttempts() {
        var loadCount = 0
        let manager = SoundManager { _ in
            loadCount += 1
            return nil
        }

        XCTAssertEqual(loadCount, SoundEffect.allCases.count)

        manager.prepare()
        manager.play(.activation)
        manager.play(.success)

        XCTAssertEqual(loadCount, SoundEffect.allCases.count)
    }

    @MainActor
    func testAccessibilityPromptIsRequestedOnlyOnce() {
        let promptCount = LockedCounter()
        let settingsOpenCount = LockedCounter()
        let manager = PermissionsManager(
            trustProvider: { false },
            promptProvider: {
                promptCount.increment()
                return false
            },
            settingsOpener: {
                settingsOpenCount.increment()
            }
        )

        manager.requestAccessibility()
        manager.requestAccessibility()
        manager.openAccessibilitySettings()

        XCTAssertEqual(promptCount.value, 1)
        XCTAssertEqual(settingsOpenCount.value, 1)
        XCTAssertTrue(manager.hasRequestedAccessibility)
    }
}
