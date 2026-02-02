//
//  ImportSeedphraseScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI
import SwiftData
import WalletCore

struct ImportSeedphraseScreen: View {
    let wordsCountType = [12, 24]

    @State private var validationTask: Task<Void, Never>?
    @State private var duplicateSeedError: Error?
    @State private var isImporting = false

    @FocusState var isFocused: Bool
    @State var mnemonicInput: String = ""
    @State var validMnemonic: Bool? = false
    @State var errorMessage: String?
    @Environment(\.router) var router
    @Environment(\.modelContext) private var modelContext

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

    /// Custom binding that prevents newlines while preserving spaces
    var mnemonicInputBinding: Binding<String> {
        Binding(
            get: { mnemonicInput },
            set: { newValue in
                // Detect if user pressed Enter/Return
                let containsNewline = newValue.contains("\n")

                // Remove newlines, preserving existing spaces
                let filtered = newValue.replacingOccurrences(of: "\n", with: "")
                mnemonicInput = filtered

                // Treat newline as submit action
                if containsNewline {
                    onImport()
                }
            }
        )
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
                        value: mnemonicInputBinding,
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
        .withError(
            error: $duplicateSeedError,
            errorType: .warning,
            buttonTitle: "tryAgain".localized
        ) {
            duplicateSeedError = nil
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFocused = true
            }
        }
        .onDisappear { isFocused = false }
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

    func onImport() {
        guard validMnemonic == true else { return }

        // Prevent concurrent import attempts
        guard !isImporting else { return }

        let cleanedMnemonic = cleanMnemonic(text: mnemonicInput)

        isImporting = true

        // Check if seed phrase is already imported
        Task {
            let isAlreadyImported = await checkIfSeedAlreadyImported(mnemonic: cleanedMnemonic)
            await MainActor.run {
                defer { isImporting = false }

                if isAlreadyImported {
                    duplicateSeedError = SeedPhraseImportError.alreadyImported
                } else {
                    isFocused = false
                    router.navigate(to: OnboardingRoute.chainsSetup(
                        mnemonic: cleanedMnemonic
                    ))
                }
            }
        }
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

    /// Checks if the seed phrase has already been imported by comparing addresses
    /// across all chains and derivation paths with existing vaults
    func checkIfSeedAlreadyImported(mnemonic: String) -> Bool {
        // Create wallet from mnemonic
        guard let wallet = HDWallet(mnemonic: mnemonic, passphrase: "") else {
            return false
        }

        // Fetch all existing vaults
        let descriptor = FetchDescriptor<Vault>()
        guard let existingVaults = try? modelContext.fetch(descriptor) else {
            return false
        }

        // Get all addresses from existing vaults
        let existingAddresses = Set(
            existingVaults.flatMap { vault in
                vault.coins.map { $0.address.lowercased() }
            }
        )

        // Generate addresses for all enabled chains and derivation paths
        let chainsToCheck = Chain.enabledChains
        let derivationPaths: [DerivationPath] = [.default, .phantom]

        for chain in chainsToCheck {
            for derivationPath in derivationPaths {
                // Generate address for this chain and derivation path
                let address: String
                if derivationPath == .phantom && chain == .solana {
                    // Use phantom derivation for Solana
                    address = wallet.getAddressDerivation(coin: chain.coinType, derivation: .solanaSolana)
                } else {
                    // Use default derivation
                    address = wallet.getAddressForCoin(coin: chain.coinType).description
                }

                // Check if this address exists in any vault
                if existingAddresses.contains(address.lowercased()) {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Error Types

enum SeedPhraseImportError: ErrorWithCustomPresentation, LocalizedError {
    case alreadyImported

    var errorTitle: String {
        switch self {
        case .alreadyImported:
            return "seedPhraseAlreadyImported".localized
        }
    }

    var errorDescription: String {
        switch self {
        case .alreadyImported:
            return "seedPhraseAlreadyImportedDescription".localized
        }
    }
}

#Preview {
    ImportSeedphraseScreen()
        .background(Theme.colors.bgPrimary)
}
