import AppKit
import Carbon
import Combine
@preconcurrency import UserNotifications
import XCTest
@testable import Kyboardclean

// Utilidades compartidas por los tests.

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

actor AsyncGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var waiterCount = 0

    func wait() async {
        waiterCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}

extension XCTestCase {
    @MainActor
    func makeSettings() -> (AppSettings, UserDefaults, String) {
        let suiteName = "KyboardcleanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (AppSettings(defaults: defaults), defaults, suiteName)
    }

    func monotonicTime(secondsAgo: TimeInterval) -> DispatchTime {
        let nanoseconds = UInt64(max(0, secondsAgo) * 1_000_000_000)
        let now = DispatchTime.now().uptimeNanoseconds
        return DispatchTime(uptimeNanoseconds: now >= nanoseconds ? now - nanoseconds : 0)
    }

    func shortcutEvent(
        keyCode: Int,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )
    }

    func overlaySnapshot(
        frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
        collectionBehavior: UInt = 0,
        isVisible: Bool = true
    ) -> OverlayWindowSnapshot {
        OverlayWindowSnapshot(
            frame: frame,
            hasContentView: true,
            level: NSWindow.Level.screenSaver.rawValue,
            collectionBehavior: collectionBehavior,
            alphaValue: 1,
            ignoresMouseEvents: false,
            presentationRequested: true,
            isVisible: isVisible,
            isMiniaturized: false,
            isOcclusionVisible: true,
            isOnActiveSpace: true
        )
    }

    func localizationSource(language: String) throws -> (values: [String: String], duplicates: [String]) {
        let url = try XCTUnwrap(
            Bundle.main.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            )
        )
        let data = try Data(contentsOf: url)
        let values = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        let source = try XCTUnwrap(
            String(data: data, encoding: .unicode) ?? String(data: data, encoding: .utf8)
        )
        let expression = try NSRegularExpression(
            pattern: #"(?m)^\s*\"((?:\\.|[^\"\\])*)\"\s*=\s*\"(?:\\.|[^\"\\])*\"\s*;\s*$"#
        )
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        var seen = Set<String>()
        var duplicates: [String] = []

        for match in matches {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let key = String(source[range])
            if !seen.insert(key).inserted {
                duplicates.append(key)
            }
        }

        return (values, duplicates)
    }

    func placeholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?[@a-zA-Z%]"#
        )
        return expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            return String(value[range])
        }
    }
}
