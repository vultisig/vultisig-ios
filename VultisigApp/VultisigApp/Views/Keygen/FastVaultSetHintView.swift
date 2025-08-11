//
//  FastVaultSetHintView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 03.02.2025.
//

import SwiftUI

struct FastVaultSetHintView: View {
    let tssType: TssType
    let vault: Vault
    let selectedTab: SetupVaultState
    let fastVaultEmail: String
    let fastVaultPassword: String
    let fastVaultExist: Bool
    
    @State var hint: String = ""
    @State var isLinkActive = false
    @FocusState var isFocused: Bool
    
    var body: some View {
        content
            .onAppear(){
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                }
            }
    }
    
    var hintField: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("setPasswordHintTitle", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.top, 16)
            
            Text(NSLocalizedString("setPasswordHintSubtitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textExtraLight)
            
            hintTextfield
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
    }
    
    var hintTextfield: some View {
        ZStack {
            HStack {
                TextEditor(text: $hint)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(Theme.colors.textExtraLight)
                    .font(Theme.fonts.bodyMMedium)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit {
                        let hasInput = !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if hasInput {
                            isLinkActive = true
                        }
                    }
                
                if !hint.isEmpty {
                    VStack {
                        clearButton
                        Spacer()
                    }
                }
            }
            if hint.isEmpty {
                VStack {
                    HStack {
                        Text(NSLocalizedString("enterHint", comment: ""))
                            .foregroundColor(Theme.colors.textExtraLight)
                            .font(Theme.fonts.bodyMMedium)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(height: 120)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
    }
    
    var clearButton: some View {
        Button {
            hint = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textExtraLight)
        }
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            PrimaryButton(
                title: "skip",
                type: .secondary
            ) {
                hint = .empty
                isLinkActive = true
            }
            PrimaryButton(title: "next") {
                isLinkActive = true
            }
            .disabled(hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }
    
    var fastSignConfig: FastSignConfig {
        return FastSignConfig(
            email: fastVaultEmail,
            password: fastVaultPassword,
            hint: hint.nilIfEmpty,
            isExist: fastVaultExist
        )
    }
}
