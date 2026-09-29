import Foundation

// Tipos auxiliares de EventTapManager: estado del tap, política de reintentos y
// sincronización con el hilo del tap.

enum TapRuntimeState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case reactivating
    case disarmedForExit
    case failed
}

struct TapReactivationAttemptPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    private(set) var completedAttempts = 0

    init(maximumAttempts: Int = 3) {
        self.maximumAttempts = max(1, maximumAttempts)
    }

    var isExhausted: Bool {
        completedAttempts >= maximumAttempts
    }

    mutating func nextAttempt() -> Int? {
        guard !isExhausted else { return nil }
        completedAttempts += 1
        return completedAttempts
    }

    mutating func reset() {
        completedAttempts = 0
    }
}

final class TapThreadCompletion: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var isCompleted = false

    init() {
        group.enter()
    }

    func complete() {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }

        isCompleted = true
        lock.unlock()
        group.leave()
    }

    func wait(timeout: DispatchTime) -> Bool {
        group.wait(timeout: timeout) == .success
    }
}
