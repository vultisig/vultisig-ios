//
//  CreateVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct CreateVaultView: View {
    var showBackButton = false
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .toolbar {
            if showBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationBackButton()
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
#endif
    }
    
    var view: some View {
        VStack {
            Spacer()
            VultisigLogo(isAnimated: false)
            Spacer()
            buttons
        }
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            newVaultButton
            importVaultButton
        }
        .padding(40)
    }
    
    var newVaultButton: some View {
        NavigationLink {
            SetupVaultView(tssType: .Keygen)
        } label: {
            FilledButton(title: "createNewVault")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
    
    var importVaultButton: some View {
        NavigationLink {
            ImportWalletView()
        } label: {
            OutlineButton(title: "importExistingVault")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
}

#Preview {
    CreateVaultView()
}
