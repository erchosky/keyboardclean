import SwiftUI

struct ActivitySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: CleaningHistoryStore
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    t("activity.empty.title"),
                    systemImage: "sparkles",
                    description: Text(t("activity.empty.detail"))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        statistics
                        historyList
                    }
                    .padding(24)
                }
            }
        }
        .alert(t("activity.clear.confirm.title"), isPresented: $confirmingClear) {
            Button(t("activity.clear.cancel"), role: .cancel) { }
            Button(t("activity.clear.confirm"), role: .destructive) {
                history.clear()
            }
        } message: {
            Text(t("activity.clear.confirm.detail"))
        }
    }

    private var statistics: some View {
        let statistics = history.statistics
        return GroupBox(t("activity.statistics.title")) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow {
                    statistic(t("activity.statistics.count"), value: String(statistics.cleaningCount))
                    statistic(t("activity.statistics.total"), value: formatDuration(statistics.totalDurationSeconds))
                }
                GridRow {
                    statistic(t("activity.statistics.last"), value: formatDate(statistics.lastCleaningDate))
                    statistic(t("activity.statistics.average"), value: formatDuration(statistics.averageDurationSeconds))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("activity.history.title"))
                    .font(.headline)
                Spacer()
                Button(t("activity.clear"), role: .destructive) {
                    confirmingClear = true
                }
                .buttonStyle(.borderless)
            }

            VStack(spacing: 0) {
                ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                    historyRow(entry)
                    if index < history.entries.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ entry: CleaningHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.outcome == .completed ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(formatDate(entry.date))
                    .font(.body.weight(.medium))
                Text(formatDuration(entry.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(t(entry.outcome == .completed ? "activity.outcome.completed" : "activity.outcome.cancelled"))
                .font(.caption.weight(.medium))
                .foregroundStyle(entry.outcome == .completed ? .green : .secondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 {
            return t("activity.duration.seconds", value)
        }
        if value < 3_600 {
            return t("activity.duration.minutes", value / 60)
        }
        return t("activity.duration.hoursMinutes", value / 3_600, (value % 3_600) / 60)
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return t("activity.statistics.never") }
        return Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(AppText.locale(for: settings.languageMode))
            .format(date)
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }

    private func t(_ key: String, _ values: CVarArg...) -> String {
        let format = AppText.string(key, language: settings.languageMode)
        return String(format: format, locale: AppText.locale(for: settings.languageMode), arguments: values)
    }
}
