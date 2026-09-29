import Carbon
import Foundation

@MainActor
private final class SessionTimerTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire(_ timer: Timer) {
        action()
    }
}

@MainActor
final class CleaningSessionManager: ObservableObject {
    static let shared = CleaningSessionManager(historyStore: .shared)

    @Published private(set) var state: CleaningState = .idle
    @Published private(set) var remainingSeconds: TimeInterval?
    @Published private(set) var totalDurationSeconds: TimeInterval?
    @Published private(set) var hardLimitRemainingSeconds: TimeInterval = CleaningDuration.hardSafetyLimitSeconds
    @Published private(set) var lastStopReason: StopReason?
    @Published private(set) var errorCode: SessionErrorCode?
    @Published private(set) var secureEventInputEnabled = false

    private let historyStore: CleaningHistoryStore
    private let eventTapManager = EventTapManager()
    private let overlayWindowController = OverlayWindowController()
    private var timer: Timer?
    private var timerTarget: SessionTimerTarget?
    private var completionPresentationTask: Task<Void, Never>?
    private var soundEnabledForCurrentSession = true
    private var pendingDuration: CleaningDuration?
    private var requestedDeadline: DispatchTime?
    private var hardLimitDeadline: DispatchTime?
    private var nextOverlayValidationDeadline: DispatchTime?
    private var overlayVisualValidation = OverlayVisualValidationTracker(failureLimit: 2)
    private var currentSessionID: UInt64 = 0
    private var secureEventInputProvider: () -> Bool = { IsSecureEventInputEnabled() }
    private var sessionStartedAt: DispatchTime?
    private var sessionStartedDate: Date?
    private var sessionStoppedAt: DispatchTime?

    nonisolated static let completionPresentationDuration: TimeInterval = 0.45

    private init(historyStore: CleaningHistoryStore) {
        self.historyStore = historyStore
    }

#if DEBUG
    convenience init(testing: Void) {
        self.init(historyStore: .shared)
    }

    convenience init(testing: Void, historyStore: CleaningHistoryStore) {
        self.init(historyStore: historyStore)
    }
#endif

    var isCleaning: Bool {
        state.isActive
    }

    var isBusy: Bool {
        state.isBusy
    }

    func startFromUserAction(duration: CleaningDuration) {
        start(duration: duration, soundEnabled: AppSettings.shared.soundEnabled)
    }

    func start(duration: CleaningDuration, soundEnabled: Bool) {
        guard !state.isBusy else {
            return
        }

        completionPresentationTask?.cancel()
        completionPresentationTask = nil

        refreshPreflightStatus()
        guard !secureEventInputEnabled else {
            errorCode = .secureEventInput
            return
        }

        guard PermissionsManager.shared.accessibilityTrusted else {
            errorCode = .accessibilityRequired
            return
        }

        soundEnabledForCurrentSession = soundEnabled
        errorCode = nil
        lastStopReason = nil

        let sessionID = beginSession()
        state = .starting

        let hardLimitStopReason = Self.hardLimitStopReason(for: duration)
        configureEventTapCallbacks(sessionID: sessionID, hardLimitStopReason: hardLimitStopReason)
        configureOverlayCallbacks(sessionID: sessionID)

        let now = DispatchTime.now()
        pendingDuration = duration
        requestedDeadline = nil
        hardLimitDeadline = Self.deadline(after: CleaningDuration.hardSafetyLimitSeconds, from: now)
        totalDurationSeconds = duration.timedSeconds
        remainingSeconds = duration.timedSeconds?.rounded(.up)
        hardLimitRemainingSeconds = CleaningDuration.hardSafetyLimitSeconds

        guard overlayWindowController.show(), overlayWindowController.isStructurallyValid else {
            resetAfterFailedStart()
            errorCode = .overlayUnavailable
            return
        }

        guard let hardLimitDeadline else {
            resetAfterFailedStart()
            errorCode = .eventTapFailed
            return
        }

        eventTapManager.start(
            sessionID: sessionID,
            hardSafetyDeadline: hardLimitDeadline
        ) { [weak self] didStart in
            guard let self, self.isCurrentSession(sessionID), self.state == .starting else {
                return
            }

            guard didStart else {
                self.resetAfterFailedStart()
                self.errorCode = .eventTapFailed
                return
            }

            self.scheduleDeferredOverlayValidation(sessionID: sessionID)
        }
    }

    private func scheduleDeferredOverlayValidation(sessionID: UInt64) {
        Task { @MainActor [weak self] in
            var validation = OverlayVisualValidationTracker(failureLimit: 3)

            for delay in OverlayValidation.startupRetryDelaysMilliseconds {
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self, self.isCurrentSession(sessionID), self.state == .starting else {
                    return
                }

                switch validation.record(isValid: self.overlayWindowController.isVisuallyValid) {
                case .valid:
                    self.completeStart(sessionID: sessionID)
                    return
                case .retry:
                    continue
                case .fail:
                    self.stop(reason: .overlayUnavailable)
                    return
                }
            }
        }
    }

    private func completeStart(sessionID: UInt64) {
        guard isCurrentSession(sessionID), state == .starting else {
            return
        }

        guard eventTapManager.isRunning, !eventTapManager.isDisarmedForExit else {
            stop(reason: .unsafeState)
            return
        }

        guard let pendingDuration else {
            stop(reason: .unsafeState)
            return
        }

        let activeAt = DispatchTime.now()
        configureDeadlines(duration: pendingDuration, now: activeAt)
        self.pendingDuration = nil
        if let hardLimitDeadline {
            let eventTapSafetyDeadline: DispatchTime
            if pendingDuration.timedSeconds == CleaningDuration.hardSafetyLimitSeconds {
                eventTapSafetyDeadline = hardLimitDeadline + .seconds(1)
            } else {
                eventTapSafetyDeadline = hardLimitDeadline
            }
            eventTapManager.updateHardSafetyDeadline(
                sessionID: sessionID,
                deadline: eventTapSafetyDeadline
            )
        }
        updateRemainingTime(now: activeAt)

        state = .active
        sessionStartedAt = activeAt
        sessionStartedDate = Date()
        overlayVisualValidation = OverlayVisualValidationTracker(failureLimit: 2)
        nextOverlayValidationDeadline = DispatchTime.now() + .seconds(1)

        if soundEnabledForCurrentSession {
            SoundManager.shared.play(.activation)
        }

        timer?.invalidate()
        timerTarget = nil

        let sessionTimerTarget = SessionTimerTarget { [weak self] in
            self?.tick()
        }
        let sessionTimer = Timer(
            timeInterval: 0.25,
            target: sessionTimerTarget,
            selector: #selector(SessionTimerTarget.fire(_:)),
            userInfo: nil,
            repeats: true
        )

        timerTarget = sessionTimerTarget
        timer = sessionTimer
        RunLoop.main.add(sessionTimer, forMode: .common)
    }

    func stop(reason: StopReason) {
        guard state.isBusy else {
            stopEventTap()
            overlayWindowController.onOverlayUnavailable = nil
            hideOverlay()
            return
        }

        if case .stopping(reason: .timerFinished) = state,
           reason != .timerFinished {
            completionPresentationTask?.cancel()
            completionPresentationTask = nil
            finalizeStop(reason: reason, wasActive: true)
            return
        }

        if state.isStopping {
            return
        }

        let wasActive = isCleaning
        if wasActive {
            sessionStoppedAt = DispatchTime.now()
        }
        state = .stopping(reason: reason)

        timer?.invalidate()
        timer = nil
        timerTarget = nil
        pendingDuration = nil
        requestedDeadline = nil
        hardLimitDeadline = nil
        nextOverlayValidationDeadline = nil
        hardLimitRemainingSeconds = CleaningDuration.hardSafetyLimitSeconds

        guard reason == .timerFinished, wasActive else {
            finalizeStop(reason: reason, wasActive: wasActive)
            return
        }

        remainingSeconds = 0
        let sessionID = currentSessionID
        completionPresentationTask?.cancel()
        completionPresentationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.completionPresentationDuration))
            guard !Task.isCancelled,
                  let self,
                  self.currentSessionID == sessionID,
                  self.state == .stopping(reason: .timerFinished) else {
                return
            }

            self.finalizeStop(reason: .timerFinished, wasActive: true)
        }
    }

    private func finalizeStop(reason: StopReason, wasActive: Bool) {
        completionPresentationTask?.cancel()
        completionPresentationTask = nil
        stopEventTap()
        overlayWindowController.onOverlayUnavailable = nil
        hideOverlay()
        remainingSeconds = nil
        totalDurationSeconds = nil

        if reason == .timerFinished, wasActive, soundEnabledForCurrentSession {
            SoundManager.shared.play(.success)
        }

        if wasActive || reason.isError {
            if reason.isError {
                if errorCode == nil {
                    errorCode = errorCode(for: reason)
                }
                lastStopReason = nil
            } else {
                errorCode = nil
                lastStopReason = reason
            }
        }

        recordHistoryIfNeeded(reason: reason, wasActive: wasActive)

        state = .idle
    }

    private func recordHistoryIfNeeded(reason: StopReason, wasActive: Bool) {
        defer {
            sessionStartedAt = nil
            sessionStartedDate = nil
            sessionStoppedAt = nil
        }

        guard wasActive, let sessionStartedAt, let sessionStartedDate else {
            return
        }

        let now = (sessionStoppedAt ?? DispatchTime.now()).uptimeNanoseconds
        let start = sessionStartedAt.uptimeNanoseconds
        let elapsed = now >= start ? Double(now - start) / 1_000_000_000 : 0
        historyStore.record(
            date: sessionStartedDate,
            durationSeconds: elapsed,
            outcome: reason == .timerFinished ? .completed : .cancelled
        )
    }

    func refreshPreflightStatus() {
        PermissionsManager.shared.refresh()
        refreshSecureEventInputState()

        if !state.isBusy,
           PermissionsManager.shared.accessibilityTrusted,
           !secureEventInputEnabled,
           isPreflightError(errorCode) {
            errorCode = nil
        }
    }

    func isCurrentSession(_ sessionID: UInt64) -> Bool {
        currentSessionID == sessionID && state.isBusy
    }

    private func beginSession() -> UInt64 {
        currentSessionID &+= 1
        return currentSessionID
    }

    private func configureEventTapCallbacks(sessionID: UInt64, hardLimitStopReason: StopReason) {
        eventTapManager.onEmergencyStop = { [weak self] in
            guard self?.isCurrentSession(sessionID) == true else { return }
            self?.stop(reason: .emergencyShortcut)
        }

        eventTapManager.onEscapeSequenceStop = { [weak self] in
            guard self?.isCurrentSession(sessionID) == true else { return }
            self?.stop(reason: .escapeSequence)
        }

        eventTapManager.onHardSafetyLimit = { [weak self] in
            guard self?.isCurrentSession(sessionID) == true else { return }
            self?.stop(reason: hardLimitStopReason)
        }

        eventTapManager.onTapFailure = { [weak self] in
            guard self?.isCurrentSession(sessionID) == true else { return }
            self?.errorCode = .eventTapFailed
            self?.stop(reason: .eventTapFailed)
        }

        eventTapManager.onSafetyFailure = { [weak self] failure in
            guard self?.isCurrentSession(sessionID) == true else { return }

            switch failure {
            case .secureEventInput:
                self?.refreshSecureEventInputState()
                self?.errorCode = .secureEventInput
                self?.stop(reason: .secureEventInput)
            case .permissionLost:
                PermissionsManager.shared.refresh()
                self?.errorCode = .permissionLost
                self?.stop(reason: .permissionLost)
            }
        }
    }

    private func configureOverlayCallbacks(sessionID: UInt64) {
        overlayWindowController.onOverlayUnavailable = { [weak self] in
            guard self?.isCurrentSession(sessionID) == true else { return }
            self?.stop(reason: .overlayUnavailable)
        }
    }

    private func tick() {
        guard isCleaning else {
            return
        }

        let now = DispatchTime.now()

        if let nextOverlayValidationDeadline,
           now >= nextOverlayValidationDeadline {
            let decision = overlayVisualValidation.record(
                isValid: overlayWindowController.isVisuallyValid
            )

            guard decision != .fail else {
                stop(reason: .overlayUnavailable)
                return
            }

            self.nextOverlayValidationDeadline = now + .seconds(1)
        }

        switch eventTapManager.runtimeState {
        case .running:
            guard eventTapManager.isRunning else {
                stop(reason: .unsafeState)
                return
            }
        case .reactivating:
            guard eventTapManager.isReactivationWithinSafetyWindow else {
                stop(reason: .unsafeState)
                return
            }
        case .disarmedForExit:
            return
        case .failed:
            stop(reason: .eventTapFailed)
            return
        case .stopped, .starting:
            stop(reason: .unsafeState)
            return
        }

        updateRemainingTime(now: now)

        if let requestedDeadline, now >= requestedDeadline {
            stop(reason: .timerFinished)
            return
        }
    }

    private func configureDeadlines(duration: CleaningDuration, now: DispatchTime) {
        requestedDeadline = duration.timedSeconds.map { Self.deadline(after: $0, from: now) }

        if duration.timedSeconds == CleaningDuration.maximumTimedSeconds,
           let requestedDeadline {
            hardLimitDeadline = requestedDeadline
        } else {
            hardLimitDeadline = Self.deadline(after: CleaningDuration.hardSafetyLimitSeconds, from: now)
        }
    }

    private func updateRemainingTime(now: DispatchTime) {
        if let requestedDeadline {
            publishRemainingSeconds(Self.remainingSeconds(until: requestedDeadline, now: now))
        } else if remainingSeconds != nil {
            remainingSeconds = nil
        }

        if let hardLimitDeadline {
            publishHardLimitRemainingSeconds(Self.remainingSeconds(until: hardLimitDeadline, now: now))
        }
    }

    nonisolated static func deadline(after seconds: TimeInterval, from now: DispatchTime) -> DispatchTime {
        now + .milliseconds(max(1, Int(seconds * 1_000)))
    }

    nonisolated static func remainingSeconds(until deadline: DispatchTime, now: DispatchTime) -> TimeInterval {
        let nowUptime = now.uptimeNanoseconds
        let deadlineUptime = deadline.uptimeNanoseconds
        guard nowUptime < deadlineUptime else {
            return 0
        }

        return Double(deadlineUptime - nowUptime) / 1_000_000_000
    }

    nonisolated static func hardLimitStopReason(for duration: CleaningDuration) -> StopReason {
        duration.timedSeconds == CleaningDuration.maximumTimedSeconds ? .timerFinished : .hardSafetyLimit
    }

    private func publishRemainingSeconds(_ seconds: TimeInterval) {
        let displayedSeconds = seconds.rounded(.up)
        if remainingSeconds != displayedSeconds {
            remainingSeconds = displayedSeconds
        }
    }

    private func publishHardLimitRemainingSeconds(_ seconds: TimeInterval) {
        let displayedSeconds = seconds.rounded(.up)
        if hardLimitRemainingSeconds != displayedSeconds {
            hardLimitRemainingSeconds = displayedSeconds
        }
    }

    private func refreshSecureEventInputState() {
        let enabled = secureEventInputProvider()
        if secureEventInputEnabled != enabled {
            secureEventInputEnabled = enabled
        }
    }

    private func isPreflightError(_ error: SessionErrorCode?) -> Bool {
        guard let error else {
            return false
        }

        return error == .accessibilityRequired
            || error == .permissionLost
            || error == .secureEventInput
    }

    private func errorCode(for reason: StopReason) -> SessionErrorCode? {
        switch reason {
        case .eventTapFailed:
            .eventTapFailed
        case .unsafeState:
            .unsafeState
        case .permissionLost:
            .permissionLost
        case .secureEventInput:
            .secureEventInput
        case .overlayUnavailable:
            .overlayUnavailable
        case .manual, .timerFinished, .emergencyShortcut, .escapeSequence, .hardSafetyLimit, .appTerminated, .systemEvent:
            nil
        }
    }

    private func resetAfterFailedStart() {
        completionPresentationTask?.cancel()
        completionPresentationTask = nil
        stopEventTap()
        overlayWindowController.onOverlayUnavailable = nil
        hideOverlay()
        remainingSeconds = nil
        totalDurationSeconds = nil
        pendingDuration = nil
        requestedDeadline = nil
        hardLimitDeadline = nil
        nextOverlayValidationDeadline = nil
        hardLimitRemainingSeconds = CleaningDuration.hardSafetyLimitSeconds
        state = .idle
    }

#if DEBUG
    func _testResetToIdle() {
        completionPresentationTask?.cancel()
        completionPresentationTask = nil
        timer?.invalidate()
        timer = nil
        timerTarget = nil
        stopEventTap()
        overlayWindowController.onOverlayUnavailable = nil
        hideOverlay()
        remainingSeconds = nil
        totalDurationSeconds = nil
        pendingDuration = nil
        requestedDeadline = nil
        hardLimitDeadline = nil
        nextOverlayValidationDeadline = nil
        hardLimitRemainingSeconds = CleaningDuration.hardSafetyLimitSeconds
        lastStopReason = nil
        errorCode = nil
        currentSessionID = 0
        sessionStartedAt = nil
        sessionStartedDate = nil
        sessionStoppedAt = nil
        secureEventInputProvider = { IsSecureEventInputEnabled() }
        secureEventInputEnabled = false
        state = .idle
    }

    func _testConfigureTiming(duration: CleaningDuration, activeAt: DispatchTime) {
        configureDeadlines(duration: duration, now: activeAt)
    }

    var _testRequestedDeadline: DispatchTime? { requestedDeadline }
    var _testHardLimitDeadline: DispatchTime? { hardLimitDeadline }

    func _testClearLifecycleEvents() {
        testLifecycleEvents.removeAll()
    }

    var _testLifecycleEvents: [String] { testLifecycleEvents }

    func _testSetTapRuntimeState(
        _ state: TapRuntimeState,
        sessionID: UInt64,
        reactivationDeadline: DispatchTime? = nil
    ) {
        eventTapManager._testSetRuntimeState(
            state,
            sessionID: sessionID,
            reactivationDeadline: reactivationDeadline
        )
    }

    func _testTick() {
        tick()
    }

    func _testMarkStarting(sessionID: UInt64) {
        currentSessionID = sessionID
        state = .starting
    }

    func _testMarkStopping(sessionID: UInt64) {
        currentSessionID = sessionID
        state = .stopping(reason: .manual)
    }

    func _testMarkActive(sessionID: UInt64, remaining: TimeInterval, total: TimeInterval) {
        currentSessionID = sessionID
        remainingSeconds = remaining
        totalDurationSeconds = total
        soundEnabledForCurrentSession = false
        sessionStartedAt = nil
        sessionStartedDate = nil
        state = .active
    }

    func _testSetSessionStart(monotonic: DispatchTime, date: Date) {
        sessionStartedAt = monotonic
        sessionStartedDate = date
    }

    var _testCurrentSessionID: UInt64 {
        currentSessionID
    }

    func _testSetSecureEventInputEnabled(_ enabled: Bool) {
        secureEventInputProvider = { enabled }
        refreshSecureEventInputState()
    }

    func _testPublishDisplayTimes(remaining: TimeInterval, hardLimit: TimeInterval) {
        publishRemainingSeconds(remaining)
        publishHardLimitRemainingSeconds(hardLimit)
    }
#endif

    private func stopEventTap() {
#if DEBUG
        testLifecycleEvents.append("eventTap.stop")
#endif
        eventTapManager.stop()
    }

    private func hideOverlay() {
#if DEBUG
        testLifecycleEvents.append("overlay.hide")
#endif
        overlayWindowController.hide()
    }

#if DEBUG
    private var testLifecycleEvents: [String] = []
#endif
}
