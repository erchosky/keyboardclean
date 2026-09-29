enum CleaningState: Equatable {
    case idle
    case starting
    case active
    case stopping(reason: StopReason)

    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .starting, .active, .stopping:
            true
        case .idle:
            false
        }
    }

    var isStopping: Bool {
        if case .stopping = self {
            return true
        }
        return false
    }
}

enum StopReason: Equatable {
    case manual
    case timerFinished
    case emergencyShortcut
    case escapeSequence
    case hardSafetyLimit
    case eventTapFailed
    case unsafeState
    case permissionLost
    case secureEventInput
    case overlayUnavailable
    case appTerminated
    case systemEvent

    var isError: Bool {
        switch self {
        case .eventTapFailed, .unsafeState, .permissionLost, .secureEventInput, .overlayUnavailable:
            true
        case .manual, .timerFinished, .emergencyShortcut, .escapeSequence, .hardSafetyLimit, .appTerminated, .systemEvent:
            false
        }
    }
}

enum SessionErrorCode: Equatable {
    case accessibilityRequired
    case secureEventInput
    case overlayUnavailable
    case eventTapFailed
    case permissionLost
    case unsafeState

    var localizationKey: String {
        switch self {
        case .accessibilityRequired:
            "error.accessibilityRequired"
        case .secureEventInput:
            "error.secureInput"
        case .overlayUnavailable:
            "error.overlayUnavailable"
        case .eventTapFailed:
            "error.eventTapFailed"
        case .permissionLost:
            "error.permissionLost"
        case .unsafeState:
            "error.unsafeState"
        }
    }
}
