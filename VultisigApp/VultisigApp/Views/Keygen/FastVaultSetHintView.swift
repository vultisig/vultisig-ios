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
    @FocusState var isFocused: Bool
    @Environment(\.router) var router

    var body: some View {
        content
            .onAppear {
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
                .foregroundColor(Theme.colors.textTertiary)
            
            hintTextfield
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
    }
    
    var hintTextfield: some View {
        CommonTextEditor(
            value: $hint,
            placeholder: "enterHint".localized,
            isFocused: $isFocused
        ) {
            let hasInput = !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasInput {
                onLinkActive()
            }
        }
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            PrimaryButton(
                title: "skip",
                type: .secondary
            ) {
                hint = .empty
                onLinkActive()
            }
            PrimaryButton(title: "next") {
                onLinkActive()
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
    
    func onLinkActive() {
        router.navigate(to: KeygenRoute.peerDiscovery(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastSignConfig: fastSignConfig,
            keyImportInput: nil,
            setupType: nil
        ))
    }
}
