import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notificationTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        registerSafetyNotifications()
        GlobalShortcutManager.shared.activate()
        ReminderManager.shared.activate(language: AppSettings.shared.languageMode)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.shouldTerminateAfterLastWindow(
            menuBarEnabled: UserDefaults.standard.bool(forKey: "menuBarEnabled"),
            shortcutRegistrationState: GlobalShortcutManager.shared.registrationState
        )
    }

    static func shouldTerminateAfterLastWindow(
        menuBarEnabled: Bool,
        shortcutRegistrationState: GlobalShortcutManager.RegistrationState
    ) -> Bool {
        !menuBarEnabled && shortcutRegistrationState != .active
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        CleaningSessionManager.shared.stop(reason: .appTerminated)
        GlobalShortcutManager.shared.deactivate()
        unregisterSafetyNotifications()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        CleaningSessionManager.shared.refreshPreflightStatus()
        ReminderManager.shared.activate(language: AppSettings.shared.languageMode)
    }

    private func registerSafetyNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CleaningSessionManager.shared.stop(reason: .systemEvent)
                }
            }
        )

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CleaningSessionManager.shared.stop(reason: .systemEvent)
                }
            }
        )

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CleaningSessionManager.shared.stop(reason: .systemEvent)
                }
            }
        )

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willPowerOffNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CleaningSessionManager.shared.stop(reason: .systemEvent)
                }
            }
        )
    }

    private func unregisterSafetyNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        for token in notificationTokens {
            workspaceCenter.removeObserver(token)
        }

        notificationTokens.removeAll()
    }
}
