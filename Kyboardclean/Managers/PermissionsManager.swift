import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var hasRequestedAccessibility = false

    private let trustProvider: () -> Bool
    private let promptProvider: () -> Bool
    private let settingsOpener: () -> Void

    init(
        trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptProvider: @escaping () -> Bool = {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        settingsOpener: @escaping () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
               NSWorkspace.shared.open(url) {
                return
            }

            if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(fallbackURL)
            }
        }
    ) {
        self.trustProvider = trustProvider
        self.promptProvider = promptProvider
        self.settingsOpener = settingsOpener
        refresh()
    }

    func refresh() {
        let trusted = trustProvider()
        if accessibilityTrusted != trusted {
            accessibilityTrusted = trusted
        }
    }

    func requestAccessibility() {
        guard !hasRequestedAccessibility else {
            refresh()
            return
        }

        hasRequestedAccessibility = true
        let trusted = promptProvider()
        if accessibilityTrusted != trusted {
            accessibilityTrusted = trusted
        }
    }

    func openAccessibilitySettings() {
        settingsOpener()
    }
}
