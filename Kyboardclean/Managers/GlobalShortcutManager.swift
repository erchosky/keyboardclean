import AppKit
import Carbon
import Foundation

#if DEBUG
struct GlobalShortcutRegistrationTestHooks {
    let installHandler: () -> OSStatus
    let register: (GlobalShortcut) -> OSStatus
    let unregister: () -> Void
    let uninstallHandler: () -> Void
}
#endif

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_K),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        keyLabel: "K"
    )

    var displayText: String {
        displayText(language: .english)
    }

    func displayText(language: AppSettings.LanguageMode) -> String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        let label = Self.specialKeyLocalizationKey(for: keyCode).map {
            AppText.string($0, language: language)
        } ?? Self.specialKeyLabel(for: keyCode) ?? keyLabel
        return symbols + label.uppercased()
    }

    var isValid: Bool {
        let supportedModifiers = [UInt32(controlKey), UInt32(optionKey), UInt32(shiftKey), UInt32(cmdKey)]
        let modifierCount = supportedModifiers.filter { carbonModifiers & $0 != 0 }.count
        let hasPrimaryModifier = carbonModifiers & UInt32(controlKey | optionKey | cmdKey) != 0
        return modifierCount >= 2
            && hasPrimaryModifier
            && keyCode != UInt32(kVK_Escape)
            && !(Self.specialKeyLabel(for: keyCode) ?? keyLabel).isEmpty
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        let relevantFlags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let modifierCount = [
            relevantFlags.contains(.control),
            relevantFlags.contains(.option),
            relevantFlags.contains(.shift),
            relevantFlags.contains(.command)
        ].filter { $0 }.count

        guard modifierCount >= 2,
              relevantFlags.contains(.control) || relevantFlags.contains(.option) || relevantFlags.contains(.command),
              event.keyCode != UInt16(kVK_Escape) else {
            return nil
        }

        let label: String
        if let specialLabel = specialKeyLabel(for: UInt32(event.keyCode)) {
            label = specialLabel
        } else if let characters = event.charactersIgnoringModifiers,
                  let key = characters.first,
                  !key.isWhitespace {
            label = String(key).uppercased()
        } else {
            return nil
        }

        var modifiers: UInt32 = 0
        if relevantFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if relevantFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if relevantFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if relevantFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

        return GlobalShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyLabel: label
        )
    }

    static func specialKeyLabel(for keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Space: "Space"
        case kVK_Tab: "Tab"
        case kVK_Return: "Return"
        case kVK_Delete: "Delete"
        case kVK_ForwardDelete: "Forward Delete"
        case kVK_Home: "Home"
        case kVK_End: "End"
        case kVK_PageUp: "Page Up"
        case kVK_PageDown: "Page Down"
        case kVK_Escape: "Escape"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        case kVK_F13: "F13"
        case kVK_F14: "F14"
        case kVK_F15: "F15"
        case kVK_F16: "F16"
        case kVK_F17: "F17"
        case kVK_F18: "F18"
        case kVK_F19: "F19"
        case kVK_F20: "F20"
        default: nil
        }
    }

    private static func specialKeyLocalizationKey(for keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_Space: "shortcut.key.space"
        case kVK_Tab: "shortcut.key.tab"
        case kVK_Return: "shortcut.key.return"
        case kVK_Delete: "shortcut.key.delete"
        case kVK_ForwardDelete: "shortcut.key.forwardDelete"
        case kVK_Home: "shortcut.key.home"
        case kVK_End: "shortcut.key.end"
        case kVK_PageUp: "shortcut.key.pageUp"
        case kVK_PageDown: "shortcut.key.pageDown"
        case kVK_Escape: "shortcut.key.escape"
        default: nil
        }
    }
}

@MainActor
final class GlobalShortcutManager: ObservableObject {
    enum RegistrationState: Equatable {
        case inactive
        case active
        case invalid
        case conflict
        case handlerFailed
        case registrationFailed
    }

    static let shared = GlobalShortcutManager()

    @Published private(set) var enabled: Bool
    @Published private(set) var shortcut: GlobalShortcut
    @Published private(set) var registrationState: RegistrationState = .inactive

    private enum Keys {
        static let enabled = "globalShortcutEnabled"
        static let shortcut = "globalShortcut"
    }

    private let defaults: UserDefaults
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

#if DEBUG
    private var testHooks: GlobalShortcutRegistrationTestHooks?
    private var testEventHandlerInstalled = false
    private var testHotKeyRegistered = false
#endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Keys.enabled)

        if let data = defaults.data(forKey: Keys.shortcut),
           let savedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = savedShortcut
        } else {
            shortcut = .defaultShortcut
        }
    }

#if DEBUG
    convenience init(defaults: UserDefaults, testHooks: GlobalShortcutRegistrationTestHooks) {
        self.init(defaults: defaults)
        self.testHooks = testHooks
    }
#endif

    func activate() {
        installEventHandlerIfNeeded()
        registerIfNeeded()
    }

    func deactivate() {
        unregister()
#if DEBUG
        if let testHooks {
            if testEventHandlerInstalled {
                testHooks.uninstallHandler()
                testEventHandlerInstalled = false
            }
            registrationState = .inactive
            return
        }
#endif
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        registrationState = .inactive
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        guard enabled else {
            unregister()
            registrationState = .inactive
            return
        }
        installEventHandlerIfNeeded()
        registerIfNeeded()
    }

    func setShortcut(_ shortcut: GlobalShortcut) {
        self.shortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Keys.shortcut)
        }
        if enabled {
            installEventHandlerIfNeeded()
        }
        registerIfNeeded()
    }

    func suspendRegistration() {
        unregister()
    }

    func resumeRegistration() {
        registerIfNeeded()
    }

    private func installEventHandlerIfNeeded() {
#if DEBUG
        if let testHooks {
            guard !testEventHandlerInstalled else { return }
            testEventHandlerInstalled = testHooks.installHandler() == noErr
            if !testEventHandlerInstalled {
                registrationState = .handlerFailed
            }
            return
        }
#endif
        guard eventHandlerReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleShortcut()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )

        if status != noErr {
            registrationState = .handlerFailed
        }
    }

    private func registerIfNeeded() {
        unregister()
#if DEBUG
        let hasEventHandler = eventHandlerReference != nil || testEventHandlerInstalled
#else
        let hasEventHandler = eventHandlerReference != nil
#endif
        guard enabled, hasEventHandler else {
            if !enabled {
                registrationState = .inactive
            } else if registrationState != .handlerFailed {
                registrationState = .handlerFailed
            }
            return
        }

        guard shortcut.isValid else {
            registrationState = .invalid
            return
        }

#if DEBUG
        if let testHooks {
            let status = testHooks.register(shortcut)
            testHotKeyRegistered = status == noErr
            registrationState = Self.registrationState(for: status)
            return
        }
#endif

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x4B594243, id: 1) // KYBC
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            registrationState = Self.registrationState(for: status)
            return
        }

        hotKeyReference = reference
        registrationState = .active
    }

    private func unregister() {
#if DEBUG
        if let testHooks {
            if testHotKeyRegistered {
                testHooks.unregister()
                testHotKeyRegistered = false
            }
            return
        }
#endif
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    private func handleShortcut() {
        guard enabled else { return }
        CleaningSessionManager.shared.startFromUserAction(duration: AppSettings.shared.selectedDuration)
    }

    private static func registrationState(for status: OSStatus) -> RegistrationState {
        if status == noErr { return .active }
        if status == eventHotKeyExistsErr { return .conflict }
        return .registrationFailed
    }

#if DEBUG
    var _testIsRegistered: Bool { testHotKeyRegistered }
    var _testHasEventHandler: Bool { testEventHandlerInstalled }
#endif
}
