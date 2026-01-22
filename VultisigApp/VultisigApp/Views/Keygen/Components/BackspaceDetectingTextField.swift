//
//  BackspaceDetectingTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-05-16.
//
#if os(macOS)
import SwiftUI
import AppKit

struct BackspaceDetectingTextField: NSViewRepresentable {
    @Binding var text: String
    var onBackspace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()

        textField.delegate = context.coordinator
        textField.isBezeled = false
        textField.isBordered = false
        textField.isEditable = true
        textField.isSelectable = true

        textField.alignment = .center
        textField.bezelStyle = .roundedBezel
        textField.isAutomaticTextCompletionEnabled = false

        textField.font = NSFont(name: "Brockmann-Medium", size: 16)
        textField.textColor = NSColor(named: "neutral0") ?? .labelColor

        textField.drawsBackground = true
        textField.backgroundColor = NSColor.clear

        textField.wantsLayer = true
        textField.layer?.cornerRadius = 12
        textField.focusRingType = .none

        return textField
    }
    // swiftlint:disable:next unused_parameter
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BackspaceDetectingTextField

        init(_ parent: BackspaceDetectingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {

            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if parent.text.isEmpty {
                    parent.onBackspace()
                    return true // handled
                }
            }

            return false // not handled, continue default behavior
        }
    }
}
#endif
