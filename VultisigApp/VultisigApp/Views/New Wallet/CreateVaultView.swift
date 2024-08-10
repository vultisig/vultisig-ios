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
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .toolbar {
            if showBackButton {
                ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                    NavigationBackButton()
                }
            }
            
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
#endif
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        CreateVaultHeader(showBackButton: showBackButton)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
}

#Preview {
    CreateVaultView()
}
