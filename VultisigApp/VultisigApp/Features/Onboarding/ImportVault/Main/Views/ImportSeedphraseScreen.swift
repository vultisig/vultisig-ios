//
//  ImportSeedphraseScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI
import WalletCore

struct ImportSeedphraseScreen: View {
    let wordsCountType = [12, 24]

    @State private var validationTask: Task<Void, Never>?

    @FocusState var isFocused: Bool
    @State var mnemonicInput: String = ""
    @State var validMnemonic: Bool? = false
    @State var errorMessage: String?
    @Environment(\.router) var router

    var importButtonDisabled: Bool {
        validMnemonic == false
    }

    var wordsCount: Int {
        cleanMnemonic(text: mnemonicInput)
            .split(separator: " ")
            .count
    }

    var wordsCountAccessory: String {
        let maxWords = wordsCount > 12 ? 24 : 12
        return "\(wordsCount)/\(maxWords)"
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        GlowIcon(icon: "import-seedphrase")
                            .padding(.bottom, 12)
                        Text("enterYourSeedphrase".localized)
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.title2)
                        CustomHighlightText(
                            "enterYourSeedphraseSubtitle".localized,
                            highlight: "enterYourSeedphraseSubtitleHighlight".localized,
                            style: Theme.colors.textPrimary,
                        )
                        .foregroundStyle(Theme.colors.textTertiary)
                        .font(Theme.fonts.bodySMedium)
                        .frame(maxWidth: 300)
                        .multilineTextAlignment(.center)
                        .fixedSize()
                    }

                    CommonTextEditor(
                        value: $mnemonicInput,
                        placeholder: "mnemonicPlaceholder".localized,
                        isFocused: $isFocused,
                        onSubmit: onImport,
                        error: $errorMessage,
                        isValid: $validMnemonic,
                        accessory: wordsCountAccessory
                    )
                    .animation(.interpolatingSpring, value: wordsCount)
                    .contentTransition(.numericText())
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                }
                Spacer()
                PrimaryButton(title: "import".localized) {
                    onImport()
                }
                .disabled(importButtonDisabled)
            }
        }
        .onLoad(perform: setup)
        .onChange(of: mnemonicInput) { oldValue, newValue in
            let cleaned = cleanMnemonic(text: newValue)
            let words = cleaned.split(separator: " ")

            if oldValue.isEmpty, words.isEmpty, wordsCountType.contains(words.count) {
                mnemonicInput = cleaned
                validateMnemonic(cleaned)
                return
            }

            // Cancel any existing validation task
            validationTask?.cancel()

            // Clear error message immediately when user is typing
            errorMessage = nil
            validMnemonic = false

            // Debounce validation by 0.5 seconds
            validationTask = Task {
                try? await Task.sleep(for: .milliseconds(500))

                guard !Task.isCancelled else { return }

                validateMnemonic(cleaned)
            }
        }
    }

    func cleanMnemonic(text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func setup() {
        isFocused = true
    }

    func onImport() {
        guard validMnemonic == true else { return }
        router.navigate(to: OnboardingRoute.chainsSetup(
            mnemonic: cleanMnemonic(text: mnemonicInput)
        ))
    }

    @MainActor
    func validateMnemonic(_ cleaned: String) {
        // Don't validate if input is empty
        guard !cleaned.isEmpty else {
            errorMessage = nil
            return
        }

        let words = cleaned.split(separator: " ")
        let wordCount = words.count

        // Check if word count is valid (12 or 24)
        guard wordsCountType.contains(wordCount) else {
            if wordCount > 0 {
                errorMessage = String(format: "seedPhraseWordCountError".localized, wordCount)
            }
            return
        }

        // Check if mnemonic is valid
        guard Mnemonic.isValid(mnemonic: cleaned) else {
            errorMessage = "seedPhraseInvalidError".localized
            return
        }

        // Valid mnemonic
        errorMessage = nil
        validMnemonic = true
    }
}

#Preview {
    ImportSeedphraseScreen()
        .background(Theme.colors.bgPrimary)
}
