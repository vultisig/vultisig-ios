//
//  NewWalletNameView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-12.
//

import SwiftUI

struct NewWalletNameView: View {
    @State var name = ""
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("nameYourVault", comment: "Name your Vault"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var view: some View {
        VStack {
            content
            Spacer()
            button
        }
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("vaultName", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)
            
            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }
    
    var textfield: some View {
        TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $name)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .submitLabel(.done)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
    }
    
    var button: some View {
        Button {
            
        } label: {
            FilledButton(title: "next")
        }
        .padding(40)
    }
}

#Preview {
    NewWalletNameView()
}
