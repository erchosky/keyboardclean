import SwiftUI

struct AutomationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shortcutManager: GlobalShortcutManager
    @EnvironmentObject private var reminderManager: ReminderManager

    var body: some View {
        Form {
            Section {
                Toggle(isOn: shortcutEnabledBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("shortcut.title"))
                        Text(t("shortcut.detail"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(t("shortcut.title"))
                .accessibilityHint(t("shortcut.detail"))

                if shortcutManager.enabled {
                    LabeledContent(t("shortcut.current")) {
                        ShortcutRecorderView(
                            shortcut: shortcutBinding,
                            prompt: t("shortcut.recording"),
                            accessibilityLabel: t("shortcut.accessibility"),
                            language: settings.languageMode,
                            onRecordingChanged: { isRecording in
                                if isRecording {
                                    shortcutManager.suspendRegistration()
                                } else {
                                    shortcutManager.resumeRegistration()
                                }
                            }
                        )
                        .frame(width: 150, height: 30)
                    }

                    if let shortcutErrorKey {
                        Label(t(shortcutErrorKey), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    } else {
                        Text(t("shortcut.requirements"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(t("settings.automation.shortcut"))
            }

            Section {
                Picker(t("reminder.title"), selection: reminderBinding) {
                    ForEach(ReminderFrequency.allCases) { frequency in
                        Text(t(frequency.localizationKey)).tag(frequency)
                    }
                }

                Text(t("reminder.detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if reminderManager.authorizationState == .denied {
                    Label(t("reminder.denied"), systemImage: "bell.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if reminderManager.authorizationState == .unavailable {
                    Label(t("reminder.unavailable"), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(t("settings.automation.reminders"))
            }

            Section {
                Label(t("settings.automation.localOnly"), systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var shortcutEnabledBinding: Binding<Bool> {
        Binding(
            get: { shortcutManager.enabled },
            set: { shortcutManager.setEnabled($0) }
        )
    }

    private var shortcutBinding: Binding<GlobalShortcut> {
        Binding(
            get: { shortcutManager.shortcut },
            set: { shortcutManager.setShortcut($0) }
        )
    }

    private var shortcutErrorKey: String? {
        switch shortcutManager.registrationState {
        case .invalid:
            "shortcut.invalid"
        case .conflict:
            "shortcut.conflict"
        case .handlerFailed:
            "shortcut.handlerFailed"
        case .registrationFailed:
            "shortcut.registrationFailed"
        case .inactive, .active:
            nil
        }
    }

    private var reminderBinding: Binding<ReminderFrequency> {
        Binding(
            get: { reminderManager.frequency },
            set: { frequency in
                Task {
                    await reminderManager.setFrequency(frequency, language: settings.languageMode)
                }
            }
        )
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }
}
