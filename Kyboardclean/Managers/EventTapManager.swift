import ApplicationServices
import Carbon
import Foundation

final class EventTapManager: @unchecked Sendable {
    typealias StartOperation = @Sendable (UInt64, DispatchTime) -> Bool

    enum SafetyFailure: Sendable {
        case secureEventInput
        case permissionLost
    }

    var onEmergencyStop: (@MainActor () -> Void)? {
        get { withCallbackLock { storedOnEmergencyStop } }
        set { withCallbackLock { storedOnEmergencyStop = newValue } }
    }
    var onEscapeSequenceStop: (@MainActor () -> Void)? {
        get { withCallbackLock { storedOnEscapeSequenceStop } }
        set { withCallbackLock { storedOnEscapeSequenceStop = newValue } }
    }
    var onHardSafetyLimit: (@MainActor () -> Void)? {
        get { withCallbackLock { storedOnHardSafetyLimit } }
        set { withCallbackLock { storedOnHardSafetyLimit = newValue } }
    }
    var onTapFailure: (@MainActor () -> Void)? {
        get { withCallbackLock { storedOnTapFailure } }
        set { withCallbackLock { storedOnTapFailure = newValue } }
    }
    var onSafetyFailure: (@MainActor (SafetyFailure) -> Void)? {
        get { withCallbackLock { storedOnSafetyFailure } }
        set { withCallbackLock { storedOnSafetyFailure = newValue } }
    }

    private let lifecycleLock = NSLock()
    private let escapeLock = NSLock()
    private let callbackLock = NSLock()
    private let startupQueue = DispatchQueue(label: "Kyboardclean.EventTapStartup")
    private let watchdogQueue = DispatchQueue(label: "Kyboardclean.EventTapWatchdog")
    private let startOperation: StartOperation?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var startResult = false
    private var isStopping = false
    private var emergencyDisarmed = false
    private var runtimeStateStorage: TapRuntimeState = .stopped
    private var reactivationPolicy = TapReactivationAttemptPolicy()
    private var reactivationGeneration: UInt64 = 0
    private var reactivationAttemptScheduled = false
    private var reactivationDeadline: DispatchTime?
    private var activeSessionID: UInt64?
    private var tapThreadGeneration: UInt64 = 0
    private var startRequestGeneration: UInt64 = 0
    private var tapThreadCompletion: TapThreadCompletion?
    private var watchdogTimer: DispatchSourceTimer?
    private var safetySupervisorTimer: DispatchSourceTimer?
    private var escapeSequence = EscapeSequenceDetector()
    private var storedOnEmergencyStop: (@MainActor () -> Void)?
    private var storedOnEscapeSequenceStop: (@MainActor () -> Void)?
    private var storedOnHardSafetyLimit: (@MainActor () -> Void)?
    private var storedOnTapFailure: (@MainActor () -> Void)?
    private var storedOnSafetyFailure: (@MainActor (SafetyFailure) -> Void)?

    private let reactivationSafetyWindow: DispatchTimeInterval = .seconds(2)
    private static let systemDefinedRawValue: UInt32 = 14
    private static let systemDefinedMask = CGEventMask(1) << CGEventMask(systemDefinedRawValue)

    init(startOperation: StartOperation? = nil) {
        self.startOperation = startOperation
    }

    var isRunning: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        guard let eventTap else {
            return false
        }

        return CFMachPortIsValid(eventTap) && CGEvent.tapIsEnabled(tap: eventTap)
    }

    var isDisarmedForExit: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        return emergencyDisarmed
    }

    var runtimeState: TapRuntimeState {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return runtimeStateStorage
    }

    var isReactivationWithinSafetyWindow: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard runtimeStateStorage == .reactivating,
              let reactivationDeadline else {
            return false
        }
        return DispatchTime.now() <= reactivationDeadline
    }

    func start(
        sessionID: UInt64,
        hardSafetyDeadline: DispatchTime,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        lifecycleLock.lock()
        startRequestGeneration &+= 1
        let requestGeneration = startRequestGeneration
        lifecycleLock.unlock()

        startupQueue.async { [weak self] in
            guard let self else {
                Task { @MainActor in completion(false) }
                return
            }

            let result: Bool
            if let startOperation = self.startOperation {
                result = self.isCurrentStartRequest(requestGeneration)
                    && startOperation(sessionID, hardSafetyDeadline)
                    && self.isCurrentStartRequest(requestGeneration)
                self.publishInjectedStartResult(
                    result,
                    requestGeneration: requestGeneration
                )
            } else {
                result = self.startSynchronously(
                    sessionID: sessionID,
                    hardSafetyDeadline: hardSafetyDeadline,
                    requestGeneration: requestGeneration
                )
            }

            Task { @MainActor in
                completion(result)
            }
        }
    }

    private func startSynchronously(
        sessionID: UInt64,
        hardSafetyDeadline: DispatchTime,
        requestGeneration: UInt64
    ) -> Bool {
        guard stop(waitForCompletion: true, clearCallbacks: false) else {
            return false
        }

        guard isCurrentStartRequest(requestGeneration) else {
            return false
        }

        let startCompletion = DispatchSemaphore(value: 0)
        let threadCompletion = TapThreadCompletion()

        lifecycleLock.lock()
        tapThreadGeneration &+= 1
        let threadGeneration = tapThreadGeneration
        lifecycleLock.unlock()

        let thread = Thread { [weak self] in
            guard let self else {
                startCompletion.signal()
                threadCompletion.complete()
                return
            }

            self.runEventTapThread(
                startCompletion: startCompletion,
                threadCompletion: threadCompletion,
                threadGeneration: threadGeneration
            )
        }
        thread.name = "Kyboardclean.EventTap"

        lifecycleLock.lock()
        guard startRequestGeneration == requestGeneration else {
            lifecycleLock.unlock()
            threadCompletion.complete()
            return false
        }

        isStopping = false
        emergencyDisarmed = false
        reactivationPolicy.reset()
        reactivationGeneration = 0
        reactivationAttemptScheduled = false
        reactivationDeadline = nil
        runtimeStateStorage = .starting
        activeSessionID = sessionID
        startResult = false
        tapThread = thread
        tapThreadCompletion = threadCompletion
        lifecycleLock.unlock()

        thread.start()

        guard startCompletion.wait(timeout: .now() + 2) == .success else {
            _ = stop(waitForCompletion: false, clearCallbacks: false)
            return false
        }

        lifecycleLock.lock()
        let result = startResult
        let requestIsCurrent = startRequestGeneration == requestGeneration
        lifecycleLock.unlock()

        if result && requestIsCurrent {
            startWatchdog(sessionID: sessionID, hardSafetyDeadline: hardSafetyDeadline)
            startSafetySupervisor(sessionID: sessionID)
        } else {
            _ = stop(waitForCompletion: false, clearCallbacks: false)
        }

        return result && requestIsCurrent
    }

    func stop() {
        lifecycleLock.lock()
        startRequestGeneration &+= 1
        lifecycleLock.unlock()
        _ = stop(waitForCompletion: false, clearCallbacks: true)
    }

    private func isCurrentStartRequest(_ generation: UInt64) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return startRequestGeneration == generation
    }

    private func publishInjectedStartResult(_ result: Bool, requestGeneration: UInt64) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard startRequestGeneration == requestGeneration else { return }
        runtimeStateStorage = result ? .running : .failed
    }

    private func withCallbackLock<T>(_ body: () -> T) -> T {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return body()
    }

    @discardableResult
    private func stop(waitForCompletion: Bool, clearCallbacks: Bool) -> Bool {
        stopWatchdog()
        stopSafetySupervisor()

        if clearCallbacks {
            onEmergencyStop = nil
            onEscapeSequenceStop = nil
            onHardSafetyLimit = nil
            onTapFailure = nil
            onSafetyFailure = nil
        }

        lifecycleLock.lock()
        isStopping = true
        emergencyDisarmed = true
        runtimeStateStorage = .disarmedForExit
        reactivationAttemptScheduled = false
        reactivationDeadline = nil
        activeSessionID = nil

        if let eventTap, CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        let runLoop = tapRunLoop
        let hasTapThread = tapThread != nil
        let completion = tapThreadCompletion
        lifecycleLock.unlock()

        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                self?.teardownTap(on: runLoop)
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !hasTapThread {
            teardownTap(on: CFRunLoopGetCurrent())
            lifecycleLock.lock()
            tapThread = nil
            tapRunLoop = nil
            startResult = false
            tapThreadCompletion = nil
            lifecycleLock.unlock()

            completion?.complete()
        }

        guard let completion else {
            return true
        }

        guard waitForCompletion else {
            return true
        }

        return completion.wait(timeout: .now() + 2)
    }

    private func runEventTapThread(
        startCompletion: DispatchSemaphore,
        threadCompletion: TapThreadCompletion,
        threadGeneration: UInt64
    ) {
        autoreleasepool {
            let currentRunLoop: CFRunLoop = CFRunLoopGetCurrent()

            lifecycleLock.lock()
            tapRunLoop = currentRunLoop
            lifecycleLock.unlock()

            let didStart = createTap(on: currentRunLoop)

            lifecycleLock.lock()
            startResult = didStart
            if tapThreadGeneration == threadGeneration, !isStopping {
                runtimeStateStorage = didStart ? .running : .failed
            }
            lifecycleLock.unlock()

            startCompletion.signal()

            if didStart {
                CFRunLoopRun()
            }

            teardownTap(on: currentRunLoop)

            lifecycleLock.lock()
            if tapThreadGeneration == threadGeneration {
                tapRunLoop = nil
                tapThread = nil
                tapThreadCompletion = nil
                startResult = false
                isStopping = false
                if runtimeStateStorage != .disarmedForExit,
                   runtimeStateStorage != .failed {
                    runtimeStateStorage = .stopped
                }
            }
            lifecycleLock.unlock()

            threadCompletion.complete()
        }
    }

    private func createTap(on runLoop: CFRunLoop) -> Bool {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel
        ]

        let mask = Self.eventMask(eventTypes) | Self.systemDefinedMask

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        lifecycleLock.lock()
        if isStopping {
            lifecycleLock.unlock()
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        lifecycleLock.unlock()

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            teardownTap(on: runLoop)
            return false
        }

        return true
    }

    private func teardownTap(on runLoop: CFRunLoop) {
        lifecycleLock.lock()
        let tap = eventTap
        let source = runLoopSource
        eventTap = nil
        runLoopSource = nil
        startResult = false
        reactivationPolicy.reset()
        reactivationGeneration &+= 1
        reactivationAttemptScheduled = false
        reactivationDeadline = nil
        lifecycleLock.unlock()

        clearEscapeSequence()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }

        if let tap {
            CFMachPortInvalidate(tap)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reactivateAfterDisable()
            return nil
        }

        if type.rawValue == Self.systemDefinedRawValue {
            return nil
        }

        switch type {
        case .keyDown:
            let key = EmergencyKeyClassifier.classify(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags
            )

            if key == .systemForceQuit {
                return Unmanaged.passUnretained(event)
            }

            if isAutoRepeat(event) {
                return nil
            }

            if key == .emergencyStop {
                let sessionID = currentSessionID()
                if let sessionID,
                   disableTapSynchronously(sessionID: sessionID, disarmEmergency: true) {
                    notifyEmergencyStop(sessionID: sessionID)
                }
                return nil
            }

            if key == .escape {
                recordEscapeForEmergencySequence()
            }

            return nil

        case .keyUp, .flagsChanged:
            return nil

        case .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel:
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func reactivateAfterDisable() {
        lifecycleLock.lock()
        let stopping = isStopping
        let disarmed = emergencyDisarmed
        let sessionID = activeSessionID

        guard !stopping && !disarmed, let sessionID else {
            lifecycleLock.unlock()
            return
        }

        guard eventTap != nil else {
            lifecycleLock.unlock()
            failReactivation(sessionID: sessionID)
            return
        }

        guard runtimeStateStorage != .reactivating else {
            lifecycleLock.unlock()
            return
        }

        runtimeStateStorage = .reactivating
        reactivationPolicy.reset()
        reactivationAttemptScheduled = false
        reactivationDeadline = DispatchTime.now() + reactivationSafetyWindow
        lifecycleLock.unlock()

        scheduleNextReactivationAttempt(sessionID: sessionID)
    }

    private func scheduleNextReactivationAttempt(sessionID: UInt64) {
        lifecycleLock.lock()
        let deadlineExpired = reactivationDeadline.map { DispatchTime.now() > $0 } ?? true
        guard activeSessionID == sessionID,
              runtimeStateStorage == .reactivating,
              !isStopping,
              !emergencyDisarmed,
              !reactivationAttemptScheduled,
              !deadlineExpired,
              !reactivationPolicy.isExhausted else {
            let shouldFail = activeSessionID == sessionID
                && runtimeStateStorage == .reactivating
                && !isStopping
                && !emergencyDisarmed
                && (deadlineExpired || reactivationPolicy.isExhausted)
            lifecycleLock.unlock()
            if shouldFail {
                failReactivation(sessionID: sessionID)
            }
            return
        }

        guard let attempt = reactivationPolicy.nextAttempt() else {
            lifecycleLock.unlock()
            failReactivation(sessionID: sessionID)
            return
        }
        reactivationGeneration &+= 1
        let generation = reactivationGeneration
        reactivationAttemptScheduled = true
        lifecycleLock.unlock()

        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(100 * attempt)) { [weak self] in
            self?.requestTapReactivation(sessionID: sessionID, generation: generation)
        }
    }

    private func requestTapReactivation(sessionID: UInt64, generation: UInt64) {
        lifecycleLock.lock()
        let runLoop = tapRunLoop
        let stopping = isStopping
        let disarmed = emergencyDisarmed
        let isCurrentSession = activeSessionID == sessionID
        let isCurrentGeneration = reactivationGeneration == generation
        if isCurrentGeneration {
            reactivationAttemptScheduled = false
        }
        lifecycleLock.unlock()

        guard let runLoop, !stopping, !disarmed, isCurrentSession, isCurrentGeneration else {
            if isCurrentSession, isCurrentGeneration, !stopping, !disarmed {
                failReactivation(sessionID: sessionID)
            }
            return
        }

        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.reactivateTapOnTapThread(sessionID: sessionID, generation: generation)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func reactivateTapOnTapThread(sessionID: UInt64, generation: UInt64) {
        lifecycleLock.lock()
        let stopping = isStopping
        let disarmed = emergencyDisarmed

        guard activeSessionID == sessionID,
              reactivationGeneration == generation,
              !stopping,
              !disarmed else {
            lifecycleLock.unlock()
            return
        }

        guard let eventTap, CFMachPortIsValid(eventTap) else {
            lifecycleLock.unlock()
            failReactivation(sessionID: sessionID)
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        let enabled = CGEvent.tapIsEnabled(tap: eventTap)
        lifecycleLock.unlock()

        if !enabled {
            scheduleNextReactivationAttempt(sessionID: sessionID)
        } else {
            scheduleStableReactivationCheck(sessionID: sessionID, generation: generation)
        }
    }

    private func scheduleStableReactivationCheck(sessionID: UInt64, generation: UInt64) {
        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self else { return }

            self.lifecycleLock.lock()
            let runLoop = self.tapRunLoop
            let isCurrent = self.activeSessionID == sessionID
                && self.reactivationGeneration == generation
                && !self.isStopping
                && !self.emergencyDisarmed
            self.lifecycleLock.unlock()

            guard let runLoop, isCurrent else {
                return
            }

            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                self?.confirmStableReactivation(sessionID: sessionID, generation: generation)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func confirmStableReactivation(sessionID: UInt64, generation: UInt64) {
        lifecycleLock.lock()
        guard activeSessionID == sessionID,
              reactivationGeneration == generation,
              runtimeStateStorage == .reactivating,
              !isStopping,
              !emergencyDisarmed else {
            lifecycleLock.unlock()
            return
        }

        let isEnabled = eventTap.map {
            CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0)
        } ?? false

        if isEnabled {
            reactivationPolicy.reset()
            reactivationDeadline = nil
            runtimeStateStorage = .running
            lifecycleLock.unlock()
        } else {
            lifecycleLock.unlock()
            scheduleNextReactivationAttempt(sessionID: sessionID)
        }
    }

    private func failReactivation(sessionID: UInt64) {
        if disableTapSynchronously(
            sessionID: sessionID,
            disarmEmergency: true,
            terminalState: .failed
        ) {
            notifyTapFailure(sessionID: sessionID)
        }
    }

    private func isAutoRepeat(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    private func recordEscapeForEmergencySequence() {
        escapeLock.lock()
        let triggered = escapeSequence.register(atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)

        if triggered {
            escapeLock.unlock()
            let sessionID = currentSessionID()
            if let sessionID,
               disableTapSynchronously(sessionID: sessionID, disarmEmergency: true) {
                notifyEscapeSequenceStop(sessionID: sessionID)
            }
            return
        }

        escapeLock.unlock()
    }

    private func clearEscapeSequence() {
        escapeLock.lock()
        escapeSequence.reset()
        escapeLock.unlock()
    }

    @discardableResult
    private func disableTapSynchronously(
        sessionID: UInt64,
        disarmEmergency: Bool,
        terminalState: TapRuntimeState = .disarmedForExit
    ) -> Bool {
        lifecycleLock.lock()
        guard activeSessionID == sessionID, !isStopping else {
            lifecycleLock.unlock()
            return false
        }

        isStopping = true
        emergencyDisarmed = emergencyDisarmed || disarmEmergency
        runtimeStateStorage = terminalState
        reactivationAttemptScheduled = false
        reactivationDeadline = nil

        if let eventTap, CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        lifecycleLock.unlock()
        return true
    }

    private func startWatchdog(sessionID: UInt64, hardSafetyDeadline: DispatchTime) {
        stopWatchdog()

        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: hardSafetyDeadline, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.handleWatchdogExpired(sessionID: sessionID)
        }

        lifecycleLock.lock()
        watchdogTimer = timer
        lifecycleLock.unlock()

        timer.resume()
    }

    func updateHardSafetyDeadline(sessionID: UInt64, deadline: DispatchTime) {
        lifecycleLock.lock()
        let isCurrent = activeSessionID == sessionID
            && !isStopping
            && runtimeStateStorage != .failed
            && runtimeStateStorage != .disarmedForExit
        lifecycleLock.unlock()

        guard isCurrent else { return }
        startWatchdog(sessionID: sessionID, hardSafetyDeadline: deadline)
    }

    private func stopWatchdog() {
        lifecycleLock.lock()
        let timer = watchdogTimer
        watchdogTimer = nil
        lifecycleLock.unlock()

        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func handleWatchdogExpired(sessionID: UInt64) {
        guard disableTapSynchronously(sessionID: sessionID, disarmEmergency: true) else {
            return
        }

        notifyHardSafetyLimit(sessionID: sessionID)
    }

    private func startSafetySupervisor(sessionID: UInt64) {
        stopSafetySupervisor()

        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            if IsSecureEventInputEnabled() {
                self.handleSafetyFailure(.secureEventInput, sessionID: sessionID)
            } else if !AXIsProcessTrusted() {
                self.handleSafetyFailure(.permissionLost, sessionID: sessionID)
            }
        }

        lifecycleLock.lock()
        safetySupervisorTimer = timer
        lifecycleLock.unlock()

        timer.resume()
    }

    private func stopSafetySupervisor() {
        lifecycleLock.lock()
        let timer = safetySupervisorTimer
        safetySupervisorTimer = nil
        lifecycleLock.unlock()

        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func handleSafetyFailure(_ failure: SafetyFailure, sessionID: UInt64) {
        guard disableTapSynchronously(sessionID: sessionID, disarmEmergency: true) else {
            return
        }

        notifySafetyFailure(failure, sessionID: sessionID)
    }

    private func currentSessionID() -> UInt64? {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return activeSessionID
    }

    private func isCurrentSession(_ sessionID: UInt64) -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return activeSessionID == sessionID
    }

    /// Entrega un aviso en el MainActor solo si la sesión sigue siendo la actual.
    private func notifyOnMainActor(
        sessionID: UInt64,
        _ deliver: @escaping @MainActor @Sendable (EventTapManager) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentSession(sessionID) else { return }
            deliver(self)
        }
    }

    private func notifyEmergencyStop(sessionID: UInt64) {
        notifyOnMainActor(sessionID: sessionID) { $0.onEmergencyStop?() }
    }

    private func notifyEscapeSequenceStop(sessionID: UInt64) {
        notifyOnMainActor(sessionID: sessionID) { $0.onEscapeSequenceStop?() }
    }

    private func notifyHardSafetyLimit(sessionID: UInt64) {
        notifyOnMainActor(sessionID: sessionID) { $0.onHardSafetyLimit?() }
    }

    private func notifyTapFailure(sessionID: UInt64) {
        notifyOnMainActor(sessionID: sessionID) { $0.onTapFailure?() }
    }

    private func notifySafetyFailure(_ failure: SafetyFailure, sessionID: UInt64) {
        notifyOnMainActor(sessionID: sessionID) { $0.onSafetyFailure?(failure) }
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | (CGEventMask(1) << CGEventMask(eventType.rawValue))
        }
    }

#if DEBUG
    func _testSetActiveSessionID(_ sessionID: UInt64) {
        lifecycleLock.lock()
        activeSessionID = sessionID
        isStopping = false
        emergencyDisarmed = false
        runtimeStateStorage = .running
        lifecycleLock.unlock()
    }

    func _testSetRuntimeState(
        _ state: TapRuntimeState,
        sessionID: UInt64,
        reactivationDeadline: DispatchTime? = nil
    ) {
        lifecycleLock.lock()
        activeSessionID = sessionID
        isStopping = state == .failed || state == .disarmedForExit
        emergencyDisarmed = state == .disarmedForExit
        runtimeStateStorage = state
        self.reactivationDeadline = reactivationDeadline
        lifecycleLock.unlock()
    }

    func _testDisarm(sessionID: UInt64) -> Bool {
        disableTapSynchronously(sessionID: sessionID, disarmEmergency: true)
    }
#endif
}
