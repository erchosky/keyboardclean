import AppKit
import SwiftUI

enum OverlayValidationDecision: Equatable {
    case valid
    case retry
    case fail
}

struct OverlayVisualValidationTracker {
    private(set) var consecutiveFailures = 0
    let failureLimit: Int

    init(failureLimit: Int) {
        self.failureLimit = max(1, failureLimit)
    }

    mutating func record(isValid: Bool) -> OverlayValidationDecision {
        if isValid {
            consecutiveFailures = 0
            return .valid
        }

        consecutiveFailures += 1
        return consecutiveFailures >= failureLimit ? .fail : .retry
    }
}

struct OverlayWindowSnapshot {
    let frame: CGRect
    let hasContentView: Bool
    let level: Int
    let collectionBehavior: UInt
    let alphaValue: CGFloat
    let ignoresMouseEvents: Bool
    let presentationRequested: Bool
    let isVisible: Bool
    let isMiniaturized: Bool
    let isOcclusionVisible: Bool
    let isOnActiveSpace: Bool
}

enum OverlayValidation {
    static let frameTolerance: CGFloat = 1
    static let startupRetryDelaysMilliseconds = [100, 150, 150]

    static func isStructurallyValid(
        screenFrames: [CGRect],
        windows: [OverlayWindowSnapshot],
        requiredLevel: Int,
        requiredCollectionBehavior: UInt
    ) -> Bool {
        guard !screenFrames.isEmpty, windows.count == screenFrames.count else {
            return false
        }

        return screenFrames.allSatisfy { screenFrame in
            windows.contains { window in
                framesMatch(window.frame, screenFrame)
                    && window.hasContentView
                    && window.level == requiredLevel
                    && window.collectionBehavior & requiredCollectionBehavior == requiredCollectionBehavior
                    && window.alphaValue > 0
                    && !window.ignoresMouseEvents
                    && window.presentationRequested
            }
        }
    }

    static func isVisuallyValid(screenFrames: [CGRect], windows: [OverlayWindowSnapshot]) -> Bool {
        guard !screenFrames.isEmpty, windows.count == screenFrames.count else {
            return false
        }

        return screenFrames.allSatisfy { screenFrame in
            windows.contains { window in
                framesMatch(window.frame, screenFrame)
                    && window.isVisible
                    && !window.isMiniaturized
                    && window.isOcclusionVisible
                    && window.isOnActiveSpace
            }
        }
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance
            && abs(lhs.minY - rhs.minY) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayWindowController {
    private var windows: [NSWindow] = []
    private var presentedWindowIDs: Set<ObjectIdentifier> = []
    private var screenChangeObserver: NSObjectProtocol?
    private var presentationGeneration: UInt64 = 0
    private(set) var isPresenting = false
    var onOverlayUnavailable: (@MainActor () -> Void)?

    var isStructurallyValid: Bool {
        guard isPresenting else {
            return false
        }

        let screens = NSScreen.screens
        return OverlayValidation.isStructurallyValid(
            screenFrames: screens.map(\.frame),
            windows: snapshots(),
            requiredLevel: NSWindow.Level.screenSaver.rawValue,
            requiredCollectionBehavior: requiredCollectionBehavior.rawValue
        )
    }

    var isVisuallyValid: Bool {
        guard isStructurallyValid else {
            return false
        }

        let screens = NSScreen.screens
        return OverlayValidation.isVisuallyValid(
            screenFrames: screens.map(\.frame),
            windows: snapshots()
        )
    }

    @discardableResult
    func show() -> Bool {
        teardownWindows()

        guard buildWindowsForCurrentScreens() else {
            return false
        }

        return isStructurallyValid
    }

    func hide() {
        teardownWindows()
    }

    private func buildWindowsForCurrentScreens() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            isPresenting = false
            return false
        }

        for screen in screens {
            let rootView = OverlayView()
                .environmentObject(CleaningSessionManager.shared)
                .environmentObject(AppSettings.shared)
                .preferredColorScheme(AppSettings.shared.appearanceMode.colorScheme)

            let hostingView = NSHostingView(rootView: rootView)
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.contentView = hostingView
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            presentedWindowIDs.insert(ObjectIdentifier(window))
        }

        isPresenting = !windows.isEmpty

        if isPresenting {
            NSApp.activate()
            startObservingScreenChanges()
        }

        return isPresenting
    }

    private func teardownWindows() {
        stopObservingScreenChanges()

        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }

        windows.removeAll()
        presentedWindowIDs.removeAll()

        isPresenting = false
        presentationGeneration &+= 1
    }

    private func startObservingScreenChanges() {
        guard screenChangeObserver == nil else {
            return
        }

        let observedGeneration = presentationGeneration
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenConfigurationChange(generation: observedGeneration)
            }
        }
    }

    private func stopObservingScreenChanges() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
    }

    private func handleScreenConfigurationChange(generation: UInt64) {
        guard isPresenting, presentationGeneration == generation else {
            return
        }

        onOverlayUnavailable?()
    }

    private var requiredCollectionBehavior: NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    private func snapshots() -> [OverlayWindowSnapshot] {
        windows.map { window in
            OverlayWindowSnapshot(
                frame: window.frame,
                hasContentView: window.contentView != nil,
                level: window.level.rawValue,
                collectionBehavior: window.collectionBehavior.rawValue,
                alphaValue: window.alphaValue,
                ignoresMouseEvents: window.ignoresMouseEvents,
                presentationRequested: presentedWindowIDs.contains(ObjectIdentifier(window)),
                isVisible: window.isVisible,
                isMiniaturized: window.isMiniaturized,
                isOcclusionVisible: window.occlusionState.contains(.visible),
                isOnActiveSpace: window.isOnActiveSpace
            )
        }
    }

#if DEBUG
    func _testSetPresentation(generation: UInt64, isPresenting: Bool) {
        presentationGeneration = generation
        self.isPresenting = isPresenting
    }

    func _testHandleScreenConfigurationChange(generation: UInt64) {
        handleScreenConfigurationChange(generation: generation)
    }
#endif
}
