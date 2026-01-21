//
//  NewWalletNameView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-12.
//

import SwiftUI
import SwiftData

struct NewWalletNameView: View {
    @Environment(\.router) var router
    let tssType: TssType
    let selectedTab: SetupVaultState

    @State var name: String
    @FocusState private var isNameFocused: Bool
    @State var errorMessage: String = ""

    @Query var vaults: [Vault]
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack {
            fields
            if !errorMessage.isEmpty {
                error
            }
            Spacer()
            button
        }
        .onAppear {
            isNameFocused = true
        }
    }
    var error: some View {
        Text(NSLocalizedString(errorMessage, comment: ""))
            .font(Theme.fonts.bodySMedium)
            .foregroundColor(Theme.colors.alertError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }
    var textfield: some View {
        HStack {
            TextField(NSLocalizedString("enterVaultName", comment: "").capitalized, text: $name)
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit {
                    verifyVault()
                }
                .maxLength($name, 64)
            
            if !name.isEmpty {
                clearButton
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
        .colorScheme(.dark)
        .borderlessTextFieldStyle()
        .autocorrectionDisabled()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(errorMessage.isEmpty ? Theme.colors.border : Theme.colors.alertError, lineWidth: 1)
        )
        .padding(.top, 32)
    }
    
    var clearButton: some View {
        Button {
            resetPlaceholderName()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Theme.colors.textTertiary)
        }
    }
    
    var button: some View {
        PrimaryButton(title: "next") {
            verifyVault()
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
    
    var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("nameYourVault", comment: ""))
                .font(Theme.fonts.largeTitle)
                .foregroundColor(Theme.colors.textPrimary)
                .padding(.top, 16)
            
            Text(NSLocalizedString("newWalletNameDescription", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textTertiary)
            
            textfield
        }
        .padding(.horizontal, 16)
    }

    private func verifyVault() {
        if name.isEmpty {
            errorMessage = NSLocalizedString("enterVaultName", comment: "")
            return
        }
        
        for vault in vaults {
            if vault.name.caseInsensitiveCompare(name) == .orderedSame {
                errorMessage = NSLocalizedString("vaultNameExists", comment: "").replacingOccurrences(of: "%s", with: name)
                return
            }
        }
        errorMessage = ""
        
        let vault = Vault(name: name)
        if selectedTab.isFastVault {
            router.navigate(to: KeygenRoute.fastVaultEmail(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultExist: false
            ))
        } else {
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: nil,
                keyImportInput: nil
            ))
        }
    }
    
    private func getVaultName() -> String {
        if name.isEmpty {
            return "Vault "
        } else {
            return name + " "
        }
    }
    
    private func resetPlaceholderName() {
        isNameFocused = false
        name = ""
        isNameFocused = true
    }
}

#Preview {
    NewWalletNameView(tssType: .Keygen, selectedTab: .fast, name: "Fast Vault #1")
}
