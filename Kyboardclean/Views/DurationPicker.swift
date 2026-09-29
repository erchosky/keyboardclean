import SwiftUI

struct DurationPicker: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("duration.title"))
                        .font(.headline)

                    Text(AppText.duration(settings.selectedDuration, language: settings.languageMode))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Picker(t("duration.picker"), selection: $settings.selectedDurationMode) {
                ForEach(AppSettings.DurationMode.primaryCases) { mode in
                    Text(t(mode.localizationKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(t("duration.picker"))

            if settings.selectedDurationMode == .custom {
                Label(
                    t("duration.custom.current", Int(settings.customDurationSeconds)),
                    systemImage: "slider.horizontal.3"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(Color(nsColor: .controlAccentColor))

                HStack(spacing: 12) {
                    Stepper(
                        value: customDurationBinding,
                        in: CleaningDuration.minimumSeconds...CleaningDuration.maximumTimedSeconds,
                        step: 10
                    ) {
                        Text(t("duration.seconds", Int(settings.customDurationSeconds)))
                            .font(.system(.body, design: .rounded))
                    }

                    TextField(
                        t("duration.seconds.placeholder"),
                        value: customDurationBinding,
                        format: .number.precision(.fractionLength(0))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }

                safetyNote(t("duration.custom.note"))
            }

            if settings.selectedDurationMode == .infinite {
                safetyNote(t("duration.manual.note"))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func safetyNote(_ text: String) -> some View {
        Label(text, systemImage: "shield.checkered")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }

    private func t(_ key: String, _ value: CVarArg) -> String {
        AppText.string(key, language: settings.languageMode, value)
    }

    private var customDurationBinding: Binding<Double> {
        Binding(
            get: { settings.customDurationSeconds },
            set: { settings.customDurationSeconds = $0 }
        )
    }
}
