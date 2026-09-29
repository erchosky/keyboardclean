import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    let prompt: String
    let accessibilityLabel: String
    let language: AppSettings.LanguageMode
    let onRecordingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onShortcut = { shortcut in
            context.coordinator.parent.shortcut = shortcut
        }
        button.onRecordingChanged = onRecordingChanged
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.parent = self
        let localizedShortcut = shortcut.displayText(language: language)
        button.shortcutText = localizedShortcut
        button.recordingPrompt = prompt
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityValue(localizedShortcut)
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: Coordinator) {
        button.finishRecording()
    }

    final class Coordinator {
        var parent: ShortcutRecorderView

        init(parent: ShortcutRecorderView) {
            self.parent = parent
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onShortcut: ((GlobalShortcut) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var shortcutText = "" { didSet { updateTitle() } }
    var recordingPrompt = "" { didSet { updateTitle() } }

    private var isRecording = false {
        didSet {
            updateTitle()
            onRecordingChanged?(isRecording)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        focusRingType = .exterior
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        guard let shortcut = GlobalShortcut.from(event: event) else {
            NSSound.beep()
            return
        }

        onShortcut?(shortcut)
        finishRecording()
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
    }

    private func updateTitle() {
        title = isRecording ? recordingPrompt : shortcutText
    }
}
