//
//  CreateVaultView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct CreateVaultView: View {
    @Binding var presentationStack: [CurrentScreen]
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            Spacer()
            VoltixLogo(isAnimated: false)
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
//        Button {
//            self.presentationStack.append(.newWalletInstructions)
//        } label: {
//            FilledButton(title: "createNewVault")
//        }
        
        NavigationLink {
            SetupVaultView()
        } label: {
            FilledButton(title: "createNewVault")
        }
    }
    
    var importVaultButton: some View {
        Button {
            self.presentationStack.append(.importWallet)
        } label: {
            OutlineButton(title: "importExistingVault")
        }
//        NavigationLink {
//            ImportWalletView2()
//        } label: {
//            OutlineButton(title: "importExistingVault")
//        }
    }
}

#Preview {
    CreateVaultView(presentationStack: .constant([]))
}
