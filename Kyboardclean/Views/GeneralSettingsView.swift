import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("menuBarEnabled") private var menuBarEnabled = false
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: CleaningSessionManager
    @EnvironmentObject private var reminderManager: ReminderManager

    var body: some View {
        Form {
            Section {
                preferenceToggle(
                    title: t("settings.general.sound"),
                    detail: t("settings.general.sound.detail"),
                    isOn: $settings.soundEnabled
                )

                preferenceToggle(
                    title: t("settings.general.menuBar"),
                    detail: t("settings.general.menuBar.detail"),
                    isOn: $menuBarEnabled
                )
            }

            Section(t("settings.appearance.title")) {
                Picker(t("settings.appearance.title"), selection: $settings.appearanceMode) {
                    Text(t("appearance.system")).tag(AppSettings.AppearanceMode.system)
                    Text(t("appearance.light")).tag(AppSettings.AppearanceMode.light)
                    Text(t("appearance.dark")).tag(AppSettings.AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(t("settings.appearance.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(t("settings.language.title")) {
                Picker(t("settings.language.title"), selection: $settings.languageMode) {
                    Text(t("language.automatic")).tag(AppSettings.LanguageMode.automatic)
                    Text(t("language.spanish")).tag(AppSettings.LanguageMode.spanish)
                    Text(t("language.english")).tag(AppSettings.LanguageMode.english)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(t("settings.language.note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(t("settings.security.title")) {
                statusRow(
                    title: t("settings.security.accessibility"),
                    value: permissions.accessibilityTrusted ? t("settings.security.granted") : t("settings.security.missing"),
                    systemImage: permissions.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: permissions.accessibilityTrusted ? .green : .orange
                )

                statusRow(
                    title: t("settings.security.secureInput"),
                    value: session.secureEventInputEnabled ? t("settings.security.active") : t("settings.security.inactive"),
                    systemImage: session.secureEventInputEnabled ? "lock.fill" : "lock.open.fill",
                    color: session.secureEventInputEnabled ? .orange : .green
                )
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onChange(of: settings.languageMode) { _, language in
            reminderManager.refreshLocalizedContent(language: language)
        }
    }

    private func preferenceToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func statusRow(title: String, value: String, systemImage: String, color: Color) -> some View {
        LabeledContent {
            Label(value, systemImage: systemImage)
                .foregroundStyle(color)
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }
}
