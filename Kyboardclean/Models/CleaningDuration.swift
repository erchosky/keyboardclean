import Foundation

enum CleaningDuration: Equatable {
    case timed(seconds: TimeInterval)
    case infinite

    static let defaultSeconds: TimeInterval = 60
    static let minimumSeconds: TimeInterval = 10
    static let maximumTimedSeconds: TimeInterval = 30 * 60
    static let hardSafetyLimitSeconds: TimeInterval = 30 * 60

    var timedSeconds: TimeInterval? {
        switch self {
        case .timed(let seconds):
            guard seconds.isFinite else {
                if seconds.isNaN {
                    return Self.defaultSeconds
                }
                return seconds.sign == .minus ? Self.minimumSeconds : Self.maximumTimedSeconds
            }
            return min(max(seconds, Self.minimumSeconds), Self.maximumTimedSeconds)
        case .infinite:
            return nil
        }
    }

}
