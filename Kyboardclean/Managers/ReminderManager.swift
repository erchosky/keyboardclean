import Foundation
@preconcurrency import UserNotifications

private actor ReminderOperationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func replace(
        cancel: @Sendable () -> Void,
        schedule: @Sendable () async throws -> Void
    ) async throws {
        await acquire()
        defer { release() }
        cancel()
        try await schedule()
    }

    func cancel(_ operation: @Sendable () -> Void) async {
        await acquire()
        defer { release() }
        operation()
    }

    private func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        waiters.removeFirst().resume()
    }
}

enum ReminderFrequency: String, CaseIterable, Identifiable, Sendable {
    case never
    case weekly
    case everyTwoWeeks
    case monthly

    var id: String { rawValue }

    var interval: TimeInterval? {
        switch self {
        case .never:
            nil
        case .weekly:
            7 * 24 * 60 * 60
        case .everyTwoWeeks:
            14 * 24 * 60 * 60
        case .monthly:
            30 * 24 * 60 * 60
        }
    }

    var localizationKey: String {
        "reminder.frequency.\(rawValue)"
    }
}

@MainActor
final class ReminderManager: ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case allowed
        case denied
        case unavailable
    }

    static let shared = ReminderManager()

    @Published private(set) var frequency: ReminderFrequency
    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var isScheduleActive = false

    typealias AuthorizationProvider = @Sendable () async -> Bool
    typealias ScheduleOperation = @Sendable (ReminderFrequency, String, String) async throws -> Void
    typealias CancelOperation = @Sendable () -> Void

    private enum Keys {
        static let frequency = "reminderFrequency"
    }

    nonisolated static let requestIdentifier = "Kyboardclean.cleaningReminder"

    private let defaults: UserDefaults
    private let authorizationProvider: AuthorizationProvider
    private let scheduleOperation: ScheduleOperation
    private let cancelOperation: CancelOperation
    private let operationGate = ReminderOperationGate()
    private var changeGeneration: UInt64 = 0

    convenience init(defaults: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()
        self.init(
            defaults: defaults,
            authorizationProvider: {
                let settings = await center.notificationSettings()
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    return true
                case .notDetermined:
                    return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
                case .denied, .ephemeral:
                    return false
                @unknown default:
                    return false
                }
            },
            scheduleOperation: { frequency, title, body in
                guard let interval = frequency.interval else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
                let request = UNNotificationRequest(
                    identifier: Self.requestIdentifier,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            },
            cancelOperation: {
                center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
            }
        )
    }

    init(
        defaults: UserDefaults,
        authorizationProvider: @escaping AuthorizationProvider,
        scheduleOperation: @escaping ScheduleOperation,
        cancelOperation: @escaping CancelOperation
    ) {
        self.defaults = defaults
        self.authorizationProvider = authorizationProvider
        self.scheduleOperation = scheduleOperation
        self.cancelOperation = cancelOperation
        frequency = defaults.string(forKey: Keys.frequency).flatMap(ReminderFrequency.init(rawValue:)) ?? .never
    }

    func activate(language: AppSettings.LanguageMode) {
        guard frequency != .never else { return }
        let savedFrequency = frequency
        Task { [weak self] in
            await self?.apply(savedFrequency, language: language, persist: false)
        }
    }

    func setFrequency(_ frequency: ReminderFrequency, language: AppSettings.LanguageMode) async {
        await apply(frequency, language: language, persist: true)
    }

    func refreshLocalizedContent(language: AppSettings.LanguageMode) {
        guard frequency != .never else { return }
        let currentFrequency = frequency
        Task { [weak self] in
            await self?.apply(currentFrequency, language: language, persist: true)
        }
    }

    private func apply(
        _ requestedFrequency: ReminderFrequency,
        language: AppSettings.LanguageMode,
        persist: Bool
    ) async {
        changeGeneration &+= 1
        let generation = changeGeneration

        if requestedFrequency == .never {
            await operationGate.cancel(cancelOperation)
            guard generation == changeGeneration else { return }
            authorizationState = .unknown
            isScheduleActive = false
            updateFrequency(.never, persist: persist)
            return
        }

        updateFrequency(requestedFrequency, persist: persist)

        let isAuthorized = await authorizationProvider()
        guard generation == changeGeneration else { return }
        guard isAuthorized else {
            await operationGate.cancel(cancelOperation)
            guard generation == changeGeneration else { return }
            authorizationState = .denied
            isScheduleActive = false
            return
        }

        do {
            let title = AppText.string("reminder.notification.title", language: language)
            let body = AppText.string("reminder.notification.body", language: language)
            try await operationGate.replace(cancel: cancelOperation) { [scheduleOperation] in
                try await scheduleOperation(requestedFrequency, title, body)
            }
            guard generation == changeGeneration else { return }
            authorizationState = .allowed
            isScheduleActive = true
        } catch {
            guard generation == changeGeneration else { return }
            authorizationState = .unavailable
            isScheduleActive = false
        }
    }

    private func updateFrequency(_ frequency: ReminderFrequency, persist: Bool) {
        self.frequency = frequency
        if persist {
            defaults.set(frequency.rawValue, forKey: Keys.frequency)
        }
    }
}
