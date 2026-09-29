import SwiftUI

enum MenuBarStartAvailability {
    static func canStart(
        accessibilityTrusted: Bool,
        secureEventInputEnabled: Bool,
        sessionIsBusy: Bool
    ) -> Bool {
        accessibilityTrusted && !secureEventInputEnabled && !sessionIsBusy
    }
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: CleaningSessionManager

    var body: some View {
        Button {
            session.startFromUserAction(duration: settings.selectedDuration)
        } label: {
            Label(t("menuBar.start"), systemImage: "lock.shield")
        }
        .disabled(!canStart)

        Menu(t("menuBar.duration")) {
            quickDuration(.thirtySeconds)
            quickDuration(.sixtySeconds)
            quickDuration(.twoMinutes)
            Divider()
            quickDuration(.infinite)
        }

        Divider()

        Button {
            openWindow(id: "main")
            NSApp.activate()
        } label: {
            Label(t("menuBar.open"), systemImage: "macwindow")
        }

        SettingsLink {
            Label(t("menu.settings"), systemImage: "gearshape")
        }

        Divider()

        Button(t("menuBar.quit")) {
            NSApp.terminate(nil)
        }
    }

    private var canStart: Bool {
        MenuBarStartAvailability.canStart(
            accessibilityTrusted: permissions.accessibilityTrusted,
            secureEventInputEnabled: session.secureEventInputEnabled,
            sessionIsBusy: session.isBusy
        )
    }

    private func quickDuration(_ mode: AppSettings.DurationMode) -> some View {
        Button {
            settings.selectedDurationMode = mode
        } label: {
            HStack {
                Text(t(mode.localizationKey))
                if settings.selectedDurationMode == mode {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }
}
