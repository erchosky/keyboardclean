import CoreGraphics

/// Clasifica una pulsación de Escape según sus modificadores. Lógica pura, sin estado del sistema.
enum EmergencyKeyClassifier {
    static let escapeKeyCode: Int64 = 53

    enum Key: Equatable, Sendable {
        /// Control + Option + Command + Escape: salida de emergencia de Kyboardclean.
        case emergencyStop
        /// Command + Option + Escape: Forzar salida de macOS; se deja pasar.
        case systemForceQuit
        /// Escape con cualquier otra combinación: cuenta para la secuencia de 5 pulsaciones.
        case escape
        case other
    }

    static func classify(keyCode: Int64, flags: CGEventFlags) -> Key {
        guard keyCode == escapeKeyCode else { return .other }

        let hasCommandAndOption = flags.contains(.maskCommand) && flags.contains(.maskAlternate)
        if hasCommandAndOption && flags.contains(.maskControl) { return .emergencyStop }
        if hasCommandAndOption { return .systemForceQuit }
        return .escape
    }
}

/// Detecta Escape pulsado 5 veces en 3 segundos. No es thread-safe: el llamador lo protege con un lock.
struct EscapeSequenceDetector: Sendable {
    static let requiredPresses = 5
    static let windowNanoseconds: UInt64 = 3_000_000_000

    private var pressTimes: [UInt64] = []

    /// Registra una pulsación; devuelve `true` (y reinicia) al completar la secuencia.
    mutating func register(atUptimeNanoseconds now: UInt64) -> Bool {
        pressTimes.append(now)
        pressTimes.removeAll { now < $0 || now - $0 > Self.windowNanoseconds }

        guard pressTimes.count >= Self.requiredPresses else { return false }
        pressTimes.removeAll()
        return true
    }

    mutating func reset() {
        pressTimes.removeAll()
    }
}
