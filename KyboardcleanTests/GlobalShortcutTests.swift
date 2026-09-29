import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

/// Atajo global, grabador de atajos y barra de menús.
final class GlobalShortcutTests: XCTestCase {
    func testGlobalShortcutDisplayAndValidation() throws {
        XCTAssertEqual(GlobalShortcut.defaultShortcut.displayText, "⌃⌥⌘K")

        let validEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.control, .option, .command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            )
        )
        let shortcut = try XCTUnwrap(GlobalShortcut.from(event: validEvent))
        XCTAssertEqual(shortcut.displayText, "⌃⌥⌘K")

        let unsafeEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: UInt16(kVK_ANSI_K)
            )
        )
        XCTAssertNil(GlobalShortcut.from(event: unsafeEvent))
    }

    func testGlobalShortcutSpecialKeyLabelsAreStableByKeyCode() {
        let expected: [(Int, String)] = [
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"),
            (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_Space, "Space"), (kVK_Tab, "Tab"),
            (kVK_Return, "Return"), (kVK_Delete, "Delete"),
            (kVK_ForwardDelete, "Forward Delete"),
            (kVK_Home, "Home"), (kVK_End, "End"),
            (kVK_PageUp, "Page Up"), (kVK_PageDown, "Page Down"),
            (kVK_Escape, "Escape"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"),
            (kVK_F4, "F4"), (kVK_F5, "F5"), (kVK_F6, "F6"),
            (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"),
            (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"),
            (kVK_F16, "F16"), (kVK_F17, "F17"), (kVK_F18, "F18"),
            (kVK_F19, "F19"), (kVK_F20, "F20")
        ]

        for (keyCode, label) in expected {
            XCTAssertEqual(GlobalShortcut.specialKeyLabel(for: UInt32(keyCode)), label)
        }
    }

    func testGlobalShortcutAllowsModifiedSpaceButRejectsUnsafeSpaceAndEscape() throws {
        let modifiedSpace = try XCTUnwrap(shortcutEvent(
            keyCode: kVK_Space,
            characters: " ",
            modifiers: [.command, .option]
        ))
        let shortcut = try XCTUnwrap(GlobalShortcut.from(event: modifiedSpace))
        XCTAssertEqual(shortcut.displayText, "⌥⌘SPACE")
        XCTAssertEqual(shortcut.displayText(language: .spanish), "⌥⌘ESPACIO")

        let plainSpace = try XCTUnwrap(shortcutEvent(keyCode: kVK_Space, characters: " "))
        XCTAssertNil(GlobalShortcut.from(event: plainSpace))

        let modifiedEscape = try XCTUnwrap(shortcutEvent(
            keyCode: kVK_Escape,
            characters: "\u{1b}",
            modifiers: [.command, .option]
        ))
        XCTAssertNil(GlobalShortcut.from(event: modifiedEscape))
    }

    @MainActor
    func testGlobalShortcutPreferencesPersist() {
        let suiteName = "KyboardcleanShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = GlobalShortcutManager(defaults: defaults)
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            keyLabel: "L"
        )

        manager.setShortcut(shortcut)
        manager.setEnabled(true)

        let restored = GlobalShortcutManager(defaults: defaults)
        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.shortcut, shortcut)
    }

    @MainActor
    func testGlobalShortcutRegistrationLifecycleDoesNotDuplicateRegistrations() {
        let suiteName = "KyboardcleanShortcutLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "globalShortcutEnabled")
        let operations = LockedArray<String>()
        let manager = GlobalShortcutManager(
            defaults: defaults,
            testHooks: GlobalShortcutRegistrationTestHooks(
                installHandler: { operations.append("install"); return noErr },
                register: { operations.append("register:\($0.displayText)"); return noErr },
                unregister: { operations.append("unregister") },
                uninstallHandler: { operations.append("uninstall") }
            )
        )

        manager.activate()
        XCTAssertEqual(manager.registrationState, .active)
        XCTAssertTrue(manager._testIsRegistered)

        manager.setShortcut(
            GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_L),
                carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
                keyLabel: "L"
            )
        )
        manager.suspendRegistration()
        manager.suspendRegistration()
        manager.resumeRegistration()
        manager.setEnabled(false)
        manager.deactivate()

        XCTAssertEqual(
            operations.values,
            ["install", "register:⌃⌥⌘K", "unregister", "register:⌃⌥⌘L", "unregister", "register:⌃⌥⌘L", "unregister", "uninstall"]
        )
        XCTAssertFalse(manager._testIsRegistered)
        XCTAssertFalse(manager._testHasEventHandler)
        XCTAssertEqual(manager.registrationState, .inactive)
    }

    @MainActor
    func testGlobalShortcutConflictRemovesPreviousRegistration() {
        let suiteName = "KyboardcleanShortcutConflictTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "globalShortcutEnabled")
        let attempts = LockedCounter()
        let unregisters = LockedCounter()
        let manager = GlobalShortcutManager(
            defaults: defaults,
            testHooks: GlobalShortcutRegistrationTestHooks(
                installHandler: { noErr },
                register: { _ in
                    attempts.increment()
                    return attempts.value == 1 ? noErr : OSStatus(eventHotKeyExistsErr)
                },
                unregister: { unregisters.increment() },
                uninstallHandler: { }
            )
        )

        manager.activate()
        XCTAssertEqual(manager.registrationState, .active)
        manager.setShortcut(
            GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_L),
                carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
                keyLabel: "L"
            )
        )

        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(unregisters.value, 1)
        XCTAssertFalse(manager._testIsRegistered)
        XCTAssertEqual(manager.registrationState, .conflict)
        manager.deactivate()
    }

    @MainActor
    func testGlobalShortcutPreservesHandlerAndRegistrationErrorsUntilRetry() {
        let suiteName = "KyboardcleanShortcutErrorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "globalShortcutEnabled")
        let installStatus = LockedValue<OSStatus>(-1)
        let registerStatus = LockedValue<OSStatus>(noErr)
        let manager = GlobalShortcutManager(
            defaults: defaults,
            testHooks: GlobalShortcutRegistrationTestHooks(
                installHandler: { installStatus.value },
                register: { _ in registerStatus.value },
                unregister: { },
                uninstallHandler: { }
            )
        )

        manager.activate()
        XCTAssertEqual(manager.registrationState, .handlerFailed)

        installStatus.set(noErr)
        registerStatus.set(-2)
        manager.activate()
        XCTAssertEqual(manager.registrationState, .registrationFailed)

        registerStatus.set(noErr)
        manager.activate()
        XCTAssertEqual(manager.registrationState, .active)

        manager.setShortcut(GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey), keyLabel: "K"))
        XCTAssertEqual(manager.registrationState, .invalid)

        manager.setEnabled(false)
        XCTAssertEqual(manager.registrationState, .inactive)
        manager.deactivate()
    }

    @MainActor
    func testShortcutRecorderFinishesExactlyOnceWhenDismissed() {
        let changes = LockedArray<Bool>()
        let button = ShortcutRecorderButton(frame: .zero)
        button.onRecordingChanged = { changes.append($0) }

        button.performClick(nil)
        button.finishRecording()
        button.finishRecording()

        XCTAssertEqual(changes.values, [true, false])
    }

    @MainActor
    func testMenuBarAndShortcutKeepOnlyValidBackgroundExitRoutes() {
        XCTAssertTrue(AppDelegate.shouldTerminateAfterLastWindow(menuBarEnabled: false, shortcutRegistrationState: .inactive))
        XCTAssertTrue(AppDelegate.shouldTerminateAfterLastWindow(menuBarEnabled: false, shortcutRegistrationState: .conflict))
        XCTAssertFalse(AppDelegate.shouldTerminateAfterLastWindow(menuBarEnabled: true, shortcutRegistrationState: .inactive))
        XCTAssertFalse(AppDelegate.shouldTerminateAfterLastWindow(menuBarEnabled: false, shortcutRegistrationState: .active))
    }

    func testMenuBarStartAvailabilityRejectsEveryUnsafeOrBusyState() {
        XCTAssertTrue(MenuBarStartAvailability.canStart(accessibilityTrusted: true, secureEventInputEnabled: false, sessionIsBusy: false))
        XCTAssertFalse(MenuBarStartAvailability.canStart(accessibilityTrusted: false, secureEventInputEnabled: false, sessionIsBusy: false))
        XCTAssertFalse(MenuBarStartAvailability.canStart(accessibilityTrusted: true, secureEventInputEnabled: true, sessionIsBusy: false))
        XCTAssertFalse(MenuBarStartAvailability.canStart(accessibilityTrusted: true, secureEventInputEnabled: false, sessionIsBusy: true))
    }

    @MainActor
    func testOneHundredShortcutRegistrationCyclesStayBalanced() {
        let suiteName = "KyboardcleanShortcutStressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "globalShortcutEnabled")
        let installs = LockedCounter()
        let registrations = LockedCounter()
        let unregisters = LockedCounter()
        let uninstalls = LockedCounter()
        let manager = GlobalShortcutManager(
            defaults: defaults,
            testHooks: GlobalShortcutRegistrationTestHooks(
                installHandler: { installs.increment(); return noErr },
                register: { _ in registrations.increment(); return noErr },
                unregister: { unregisters.increment() },
                uninstallHandler: { uninstalls.increment() }
            )
        )

        manager.activate()
        for _ in 0..<100 {
            manager.suspendRegistration()
            manager.resumeRegistration()
        }
        manager.deactivate()

        XCTAssertEqual(installs.value, 1)
        XCTAssertEqual(registrations.value, 101)
        XCTAssertEqual(unregisters.value, 101)
        XCTAssertEqual(uninstalls.value, 1)
        XCTAssertEqual(manager.registrationState, .inactive)
    }
}
