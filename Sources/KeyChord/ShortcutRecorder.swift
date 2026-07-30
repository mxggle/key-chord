import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var key: String
    @Binding var modifiers: [ShortcutModifier]
    var onShortcutChange: ((String, [ShortcutModifier]) -> Void)?

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onShortcutChange = { newKey, newModifiers in
            if let onShortcutChange {
                onShortcutChange(newKey, newModifiers)
            } else {
                key = newKey
                modifiers = newModifiers
            }
        }
        control.key = key
        control.modifiers = modifiers
        return control
    }

    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.key = key
        control.modifiers = modifiers
        control.needsDisplay = true
    }
}

@MainActor
final class ShortcutRecorderControl: NSButton {
    var key = "" {
        didSet { updatePresentation() }
    }
    var modifiers: [ShortcutModifier] = [] {
        didSet { updatePresentation() }
    }
    var onShortcutChange: ((String, [ShortcutModifier]) -> Void)?

    private var isRecording = false {
        didSet { updatePresentation() }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 26) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = displayText
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        controlSize = .small
        alignment = .center
        font = .systemFont(ofSize: 12, weight: .semibold)
        focusRingType = .default
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Keyboard shortcut")
        setAccessibilityHelp("Click, then press a key combination. Press Delete to clear it or Escape to cancel.")
        toolTip = "Click to record a new shortcut. Press Delete to clear it."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    override func accessibilityLabel() -> String? {
        "Keyboard shortcut"
    }

    override func accessibilityValue() -> Any? {
        displayText
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        isRecording = true
        return true
    }

    private func updatePresentation() {
        title = displayText
        contentTintColor = isRecording ? .controlAccentColor : .labelColor
    }

    private var displayText: String {
        if isRecording {
            return "Press shortcut…"
        }
        guard !key.isEmpty, !modifiers.isEmpty else {
            return "Record Shortcut"
        }
        let order: [ShortcutModifier] = [.control, .option, .shift, .command]
        return order.filter(modifiers.contains).map(\.symbol).joined() + key.uppercased()
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var capturedModifiers: [ShortcutModifier] = []
        if flags.contains(.control) { capturedModifiers.append(.control) }
        if flags.contains(.option) { capturedModifiers.append(.option) }
        if flags.contains(.shift) { capturedModifiers.append(.shift) }
        if flags.contains(.command) { capturedModifiers.append(.command) }

        // Delete or Backspace with no modifiers clears the recorded shortcut,
        // matching the behavior of system shortcut recorders.
        if (event.keyCode == 51 || event.keyCode == 117), capturedModifiers.isEmpty {
            key = ""
            modifiers = []
            onShortcutChange?("", [])
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        guard !capturedModifiers.isEmpty,
              let capturedKey = KeyCodeResolver.key(for: UInt32(event.keyCode)) else {
            NSSound.beep()
            return
        }

        key = capturedKey
        modifiers = capturedModifiers
        onShortcutChange?(capturedKey, capturedModifiers)
        isRecording = false
        window?.makeFirstResponder(nil)
    }
}
