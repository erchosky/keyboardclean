import SwiftUI

enum OverlayVisualPhase: Equatable {
    case preparing
    case active
    case completed

    init(state: CleaningState) {
        switch state {
        case .starting:
            self = .preparing
        case .stopping(reason: .timerFinished):
            self = .completed
        case .idle, .active, .stopping:
            self = .active
        }
    }

    static func usesDrawnCheck(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

struct OverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var session: CleaningSessionManager
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            GeometryReader { proxy in
                let compact = proxy.size.height < 700 || proxy.size.width < 760

                VStack(spacing: compact ? 18 : 28) {
                    statusHeader(compact: compact)

                    timerView(compact: compact)
                        .scaleEffect(reduceMotion || visualPhase != .preparing ? 1 : 0.98)
                        .opacity(visualPhase == .preparing ? 0.9 : 1)
                        .animation(stateTransitionAnimation, value: visualPhase)
                    cleaningReminder
                    stopPanel(compact: compact)
                    safetyLine
                }
                .padding(compact ? 24 : 48)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .environment(\.locale, AppText.locale(for: settings.languageMode))
    }

    private func statusHeader(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                Text(t("overlay.badge"))
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12), in: Capsule())

            ZStack {
                statusCopy(compact: compact, preparing: true)
                    .opacity(visualPhase == .preparing ? 1 : 0)
                    .scaleEffect(reduceMotion || visualPhase == .preparing ? 1 : 0.98)
                    .accessibilityHidden(visualPhase != .preparing)

                statusCopy(compact: compact, preparing: false)
                    .opacity(visualPhase == .preparing ? 0 : 1)
                    .scaleEffect(reduceMotion || visualPhase != .preparing ? 1 : 0.98)
                    .accessibilityHidden(visualPhase == .preparing)
            }
            .animation(stateTransitionAnimation, value: visualPhase)
        }
    }

    private func statusCopy(compact: Bool, preparing: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            Text(preparing ? t("overlay.title.starting") : t("overlay.title.active"))
                .font(.system(size: compact ? 38 : 52, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.72)

            Text(preparing ? t("overlay.subtitle.starting") : t("overlay.subtitle.active"))
                .font(.system(size: compact ? 17 : 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var background: some View {
        Color(nsColor: .windowBackgroundColor)
            .opacity(reduceTransparency ? 1 : 0.96)
            .overlay(Color.accentColor.opacity(0.06))
    }

    @ViewBuilder
    private func timerView(compact: Bool) -> some View {
        if let remaining = session.remainingSeconds {
            OverlayTimedProgressView(
                remaining: remaining,
                total: session.totalDurationSeconds,
                compact: compact,
                completed: visualPhase == .completed,
                reduceMotion: reduceMotion,
                remainingLabel: t("overlay.remaining"),
                completedLabel: t("overlay.completed")
            )
        } else {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: compact ? 10 : 12)

                VStack(spacing: 6) {
                    Image(systemName: "infinity")
                        .font(.system(size: compact ? 56 : 72, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(t("overlay.manual"))
                        .font(.title2.weight(.semibold))

                    Text(t("overlay.hardLimit", formatTime(session.hardLimitRemainingSeconds)))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: compact ? 220 : 280, height: compact ? 220 : 280)
        }
    }

    private var cleaningReminder: some View {
        Label(t("overlay.cleaningTip"), systemImage: "sparkles")
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 640)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stopPanel(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            Text(t("overlay.stopTitle"))
                .font(.system(size: compact ? 26 : 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(alignment: .leading, spacing: 9) {
                Label(t("overlay.shortcut"), systemImage: "command")
                Label(t("overlay.escape"), systemImage: "escape")
                Label(t("overlay.noKeys"), systemImage: "eye.slash")
            }
            .font(.system(size: compact ? 15 : 17, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, compact ? 24 : 36)
        .padding(.vertical, compact ? 18 : 24)
        .frame(maxWidth: 620)
        .background(Color.red.opacity(reduceTransparency ? 0.16 : 0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var safetyLine: some View {
        Text(t("overlay.mouseNotice"))
            .font(.callout.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 640)
            .accessibilityLabel(t("overlay.mouseNotice"))
    }

    private var visualPhase: OverlayVisualPhase {
        OverlayVisualPhase(state: session.state)
    }

    private var stateTransitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .easeOut(duration: 0.22)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        let minutes = value / 60
        let remainder = value % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func t(_ key: String) -> String {
        AppText.string(key, language: settings.languageMode)
    }

    private func t(_ key: String, _ value: CVarArg) -> String {
        AppText.string(key, language: settings.languageMode, value)
    }
}

private struct OverlayTimedProgressView: View {
    let remaining: TimeInterval
    let total: TimeInterval?
    let compact: Bool
    let completed: Bool
    let reduceMotion: Bool
    let remainingLabel: String
    let completedLabel: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: lineWidth)

            ZStack {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress)

                VStack(spacing: 5) {
                    Text(formatTime(remaining))
                        .font(.system(size: compact ? 52 : 68, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(remainingLabel)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(completed ? 0 : 1)
            .scaleEffect(reduceMotion || !completed ? 1 : 0.98)
            .animation(.easeOut(duration: 0.16), value: completed)

            completionCheck
        }
        .frame(width: compact ? 220 : 280, height: compact ? 220 : 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(completed ? completedLabel : remainingLabel)
        .accessibilityValue(completed ? completedLabel : formatTime(remaining))
    }

    @ViewBuilder
    private var completionCheck: some View {
        if reduceMotion {
            Image(systemName: "checkmark")
                .font(.system(size: compact ? 70 : 88, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(completed ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: completed)
        } else {
            OverlayCompletionCheckmark()
                .trim(from: 0, to: completed ? 1 : 0)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: compact ? 12 : 14, lineCap: .round, lineJoin: .round)
                )
                .frame(width: compact ? 82 : 104, height: compact ? 62 : 78)
                .animation(.easeOut(duration: 0.28).delay(0.12), value: completed)
        }
    }

    private var lineWidth: CGFloat {
        compact ? 10 : 12
    }

    private var progress: CGFloat {
        guard let total, total > 0 else {
            return 0
        }

        return min(1, max(0, remaining / total))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct OverlayCompletionCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.12))
        return path
    }
}

#if DEBUG
#Preview("Timer active") {
    OverlayTimedProgressView(
        remaining: 18,
        total: 30,
        compact: false,
        completed: false,
        reduceMotion: false,
        remainingLabel: "Tiempo restante",
        completedLabel: "Limpieza completada"
    )
    .padding(40)
}

#Preview("Timer completed") {
    OverlayTimedProgressView(
        remaining: 0,
        total: 30,
        compact: false,
        completed: true,
        reduceMotion: false,
        remainingLabel: "Tiempo restante",
        completedLabel: "Limpieza completada"
    )
    .padding(40)
}

#Preview("Timer cancelled") {
    OverlayTimedProgressView(
        remaining: 12,
        total: 30,
        compact: true,
        completed: false,
        reduceMotion: false,
        remainingLabel: "Tiempo restante",
        completedLabel: "Limpieza completada"
    )
    .padding(32)
}

#Preview("Timer Reduce Motion") {
    OverlayTimedProgressView(
        remaining: 0,
        total: 30,
        compact: false,
        completed: true,
        reduceMotion: true,
        remainingLabel: "Tiempo restante",
        completedLabel: "Limpieza completada"
    )
    .padding(40)
}
#endif
