//
//  PasscodeInput.swift
//  VultisigApp
//

import SwiftUI

struct PasscodeInputActions {
    let append: (String) -> Void
    let deleteLast: () -> Void
}

enum PasscodeInputRules {
    static func appending(_ digit: String, to entry: String) -> String? {
        guard entry.count < PasscodeService.passcodeLength else { return nil }
        return entry + digit
    }

    static func deletingLast(from entry: String) -> String? {
        entry.isEmpty ? nil : String(entry.dropLast())
    }

    static func pastedEntry(from value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.count <= PasscodeService.passcodeLength,
              candidate.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return candidate
    }

    static func acceptsNativeEntry(_ value: String) -> Bool {
        value.count <= PasscodeService.passcodeLength
            && value.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Owns passcode input behavior while leaving each flow free to present its own
/// dots and input surface. Settings keeps its circular keypad, while app lock
/// uses the native iOS number pad or macOS hardware keyboard without duplicating
/// input rules.
struct PasscodeInput<Content: View>: View {
    @Binding var passcode: String
    let isBusy: Bool
    let onComplete: (String) -> Void
    let content: (PasscodeInputActions) -> Content

    #if os(macOS)
    @FocusState private var isKeypadFocused: Bool
    @State private var keyboard = KeyboardEntry()

    private final class KeyboardEntry {
        var expected: String?
    }
    #endif

    init(
        passcode: Binding<String>,
        isBusy: Bool,
        onComplete: @escaping (String) -> Void,
        @ViewBuilder content: @escaping (PasscodeInputActions) -> Content
    ) {
        _passcode = passcode
        self.isBusy = isBusy
        self.onComplete = onComplete
        self.content = content
    }

    var body: some View {
        content(actions)
            .onChange(of: passcode) { _, value in
                guard value.count == PasscodeService.passcodeLength else { return }
                onComplete(value)
            }
            #if os(macOS)
            .focusable()
            .focusEffectDisabled()
            .focused($isKeypadFocused)
            .onAppear { isKeypadFocused = true }
            .onKeyPress(phases: [.down, .repeat]) { handleKeyPress($0) }
            #endif
    }

    private var actions: PasscodeInputActions {
        PasscodeInputActions(
            append: { digit in apply { PasscodeInputRules.appending(digit, to: $0) } },
            deleteLast: { apply(PasscodeInputRules.deletingLast) }
        )
    }

    private func apply(_ edit: (String) -> String?) {
        guard !isBusy, let next = edit(passcode) else { return }
        passcode = next
        confirmEntry()
    }

    private func confirmEntry() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #else
        isKeypadFocused = true
        #endif
    }

    #if os(macOS)
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.capsLock, .numericPad])

        if modifiers.contains(.command) {
            guard modifiers == .command, press.phase == .down, press.characters == "v" else {
                return .ignored
            }
            guard let pasted = clipboardPasscode() else { return .handled }
            return enqueue { _ in pasted }
        }

        guard modifiers.isEmpty else { return .ignored }

        let isDelete = press.key == .delete || press.key == .deleteForward
        guard press.phase == .down || isDelete else { return .ignored }

        if isDelete {
            return enqueue(PasscodeInputRules.deletingLast)
        }

        guard press.characters.count == 1,
              let digit = press.characters.first,
              digit.isASCII, digit.isNumber else {
            return .ignored
        }

        return enqueue { PasscodeInputRules.appending(String(digit), to: $0) }
    }

    /// Hardware keys arrive while the macOS lock panel may be mid-update. Queue
    /// them onto the next main turn and judge each one against the entry formed
    /// by earlier queued keys, preserving order without publishing in-render.
    private func enqueue(_ edit: (String) -> String?) -> KeyPress.Result {
        let base = keyboard.expected ?? passcode
        guard !isBusy,
              let next = edit(base) else {
            return .handled
        }
        keyboard.expected = next

        DispatchQueue.main.async {
            guard passcode == base else {
                keyboard.expected = nil
                return
            }
            passcode = next
            if keyboard.expected == next {
                keyboard.expected = nil
            }
            confirmEntry()
        }
        return .handled
    }

    private func clipboardPasscode() -> String? {
        guard let pasted = ClipboardManager.pasteFromClipboard() else { return nil }
        return PasscodeInputRules.pastedEntry(from: pasted)
    }
    #endif
}
