//
//  ImportSeedphraseView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 01/12/2025.
//

import SwiftUI
import WalletCore

struct ImportSeedphraseView: View {
    let wordsCount = [12, 24]
    
    @State var selectedWordsCount: Int = 12
    @State var words: [String] = []
    @State private var presentPeersScreen: Bool = false
    
    @FocusState private var focusedField: Int?
    
    var isValidMnemonic: Bool {
        Mnemonic.isValid(mnemonic: words.joined(separator: " "))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            wordsButtonStack
                .padding(.bottom, 16)
            Separator(color: Theme.colors.borderLight, opacity: 1)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(0..<(words.count / 2), id: \.self) { row in
                        HStack(spacing: 16) {
                            WordInputRow(
                                index: row * 2,
                                word: $words[row * 2],
                                focusedField: $focusedField,
                                totalWords: words.count,
                                onPaste: handlePastedSeedPhrase
                            )
                            
                            WordInputRow(
                                index: row * 2 + 1,
                                word: $words[row * 2 + 1],
                                focusedField: $focusedField,
                                totalWords: words.count,
                                onPaste: handlePastedSeedPhrase
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .contentMargins(.vertical, 16)
            .padding(.bottom, 16)
            .overlay(overlay)
            
            PrimaryButton(title: "import".localized) {
                onImport()
            }
            .disabled(!isValidMnemonic)
        }
        .onLoad(perform: setup)
        .onChange(of: selectedWordsCount) { _, _ in
            setup()
        }
        .animation(.easeInOut(duration: 0.2), value: focusedField)
        .padding(.top, 24)
        .navigationDestination(isPresented: $presentPeersScreen) {
            PeerDiscoveryView(
                tssType: .KeyImport,
                vault: Vault(name: "Test seedphrase", libType: .KeyImport),
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: KeyImportInput(
                    mnemnonic: words.joined(separator: " "),
                    chains: [.bitcoin]
                )
            )
        }
    }
    
    var wordsButtonStack: some View {
        HStack(spacing: 8) {
            ForEach(wordsCount, id: \.hashValue) { words in
                Button {
                    selectedWordsCount = words
                } label: {
                    Text("\(words) words")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.caption12)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 99)
                                .fill(Theme.colors.bgButtonTertiary)
                                .showIf(selectedWordsCount == words)
                                .animation(.interpolatingSpring, value: selectedWordsCount)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var overlay: some View {
        VStack {
            LinearGradient(
                colors: [Theme.colors.bgPrimary, .clear],
                startPoint: .top,
                endPoint: .bottom
            ).frame(height: 16)
            Spacer()
            LinearGradient(
                colors: [Theme.colors.bgPrimary, .clear],
                startPoint: .bottom,
                endPoint: .top
            ).frame(height: 32)
        }
    }
    
    func setup() {
        words = Array(repeating: "", count: selectedWordsCount)
    }
    
    func handlePastedSeedPhrase(_ pastedText: String) {
        let components = pastedText.split(separator: " ").map(String.init)
        
        // Check if it's a valid 12 or 24 word seed phrase
        if components.count == 12 || components.count == 24 {
            // Auto-switch to the correct word count if needed
            if components.count != selectedWordsCount {
                selectedWordsCount = components.count
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                words = components
                
                // Dismiss keyboard if the pasted mnemonic is valid
                if Mnemonic.isValid(mnemonic: pastedText) {
                    focusedField = nil
                }
            }
        }
    }
    
    func onImport() {
        presentPeersScreen = true
    }
}

struct WordInputRow: View {
    let index: Int
    @Binding var word: String
    @FocusState.Binding var focusedField: Int?
    let totalWords: Int
    let onPaste: (String) -> Void
    
    @State var isValidWord: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.colors.bgSecondary)
                )
            
            CommonTextField(
                text: $word,
                placeholder: "",
                error: Binding(get: { !isValidWord && word.isNotEmpty ? "word-error" : nil }, set: { _ in }),
                isValid: Binding(get: { isValidWord }, set: { _ in }),
                showErrorText: false,
                size: .small,
            )
            .autocorrectionDisabled()
            .focused($focusedField, equals: index)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.next)
            #endif
            .onSubmit {
                if index < totalWords - 1 {
                    focusedField = index + 1
                } else {
                    focusedField = nil
                }
            }
            .onChange(of: word) { _, newValue in
                handlePaste(newValue: newValue)
                isValidWord = Mnemonic.isValidWord(word: newValue)
            }
        }
    }
    
    private func handlePaste(newValue: String) {
        // Check if this looks like a paste operation (multiple words added at once)
        let components = newValue.split(separator: " ")
        guard components.count > 1 else { return }
        onPaste(newValue)
    }
}

#Preview {
    ImportSeedphraseView()
        .background(Theme.colors.bgPrimary)
}
