import SwiftUI

struct MainView: View {
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: CleaningSessionManager

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    introduction
                    statusPanel
                    DurationPicker()
                    exitHint
                    actionRow
                    footerMessage
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Kyboardclean")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(t("main.settings"))
            .accessibilityLabel(t("main.settings"))
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(t("main.title"))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(t("main.subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.headline)
                        .layoutPriority(1)

                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(statusBadge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusTitle)
            .accessibilityValue(statusDetail)

            if !permissions.accessibilityTrusted {
                permissionActions
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var actionRow: some View {
        Group {
            if permissions.accessibilityTrusted {
                Button {
                    session.startFromUserAction(duration: settings.selectedDuration)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield")
                        Text(t("main.start"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(KyboardcleanPrimaryCTAButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(session.secureEventInputEnabled || session.isBusy)
                .help(startButtonHelp)
                .accessibilityHint(startButtonHelp)
            }
        }
    }

    private var permissionActions: some View {
        HStack(spacing: 10) {
            Button {
                permissions.requestAccessibility()
                session.refreshPreflightStatus()
            } label: {
                Label(t("permission.grant"), systemImage: "hand.raised.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            if permissions.hasRequestedAccessibility {
                Button(t("permission.openSettings")) {
                    permissions.openAccessibilitySettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var exitHint: some View {
        Label(t("main.exitHint"), systemImage: "escape")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private var startButtonHelp: String {
        if !permissions.accessibilityTrusted {
            return t("main.startHelp.permission")
        }

        if session.secureEventInputEnabled {
            return t("main.startHelp.secureInput")
        }

        return t("main.startHelp.ready")
    }

    @ViewBuilder
    private var footerMessage: some View {
        if let errorCode = session.errorCode {
            footer(AppText.sessionError(errorCode, language: settings.languageMode), systemImage: "exclamationmark.triangle.fill", color: .orange)
        } else if let reason = session.lastStopReason {
            footer(AppText.stopReason(reason, language: settings.languageMode), systemImage: reason.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", color: reason.isError ? .orange : .green)
        } else {
            footer(t("main.privacyNote"), systemImage: "eye.slash", color: .secondary)
        }
    }

    private func footer(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusTitle: String {
        if !permissions.accessibilityTrusted {
            return t("status.permissionMissing.title")
        }
        if session.secureEventInputEnabled {
            return t("status.secureInput.title")
        }
        if session.state == .starting {
            return t("status.starting.title")
        }
        if session.isBusy {
            return t("status.active.title")
        }
        return t("status.ready.title")
    }

    private var statusDetail: String {
        if !permissions.accessibilityTrusted {
            return t("status.permissionMissing.detail")
        }
        if session.secureEventInputEnabled {
            return t("status.secureInput.detail")
        }
        if session.state == .starting {
            return t("status.starting.detail")
        }
        if session.isBusy {
            return t("status.active.detail")
        }
        return t("status.ready.detail")
    }

    private var statusBadge: String {
        if !permissions.accessibilityTrusted {
            return t("status.badge.required")
        }
        if session.secureEventInputEnabled {
            return t("status.badge.blocked")
        }
        if session.state == .starting {
            return t("status.badge.starting")
        }
        if session.isBusy {
            return t("status.badge.active")
        }
        return t("status.badge.ready")
    }

    private var statusIcon: String {
        if !permissions.accessibilityTrusted {
            return "lock.trianglebadge.exclamationmark.fill"
        }
        if session.secureEventInputEnabled {
            return "lock.shield.fill"
        }
        if session.isBusy {
            return "keyboard.badge.ellipsis"
        }
        return "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if !permissions.accessibilityTrusted || session.secureEventInputEnabled {
            return .orange
        }
        if session.isBusy {
            return Color(nsColor: .controlAccentColor)
        }
        return .green
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }
}

private struct KyboardcleanPrimaryCTAButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .background(
                Color.accentColor.opacity(isEnabled ? 1 : 0.48),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.975 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.2, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}
