//
//  RegisterVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

import SwiftUI

struct RegisterVaultView: View {
    let vault: Vault
    
    @StateObject var viewModel = VaultDetailQRCodeViewModel()
    
    @State var imageName = ""
    @State var isExporting: Bool = false
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .onAppear {
            setData()
        }
    }
    
    var image: some View {
        VultisigLogo(showTexts: false)
            .padding(.vertical, 30)
    }
    
    var text1: some View {
        Text(NSLocalizedString("registerVaultText1", comment: ""))
    }
    
    var text2: some View {
        HStack {
            Text(NSLocalizedString("registerVaultText2", comment: ""))
            webButton
        }
    }
    
    var text3: some View {
        Text(NSLocalizedString("registerVaultText3", comment: ""))
    }
    
    var text4: some View {
        Text(NSLocalizedString("registerVaultText4", comment: ""))
    }
    
    var webButton: some View {
        Link(destination: StaticURL.VultisigWeb) {
            webLabel
        }
    }
    
    var webLabel: some View {
        Text("Vultisig Web")
            .foregroundColor(.turquoise600)
            .padding(.vertical, 12)
            .padding(.horizontal, 28)
            .background(Color.blue600)
            .cornerRadius(10)
    }
    
    var label: some View {
        FilledButton(title: "complete")
            .padding(.bottom, 20)
    }
    
    private func setData() {
        imageName = viewModel.generateName(vault: vault)
        viewModel.render(vault: vault, displayScale: displayScale)
    }
}

#Preview {
    RegisterVaultView(vault: Vault.example)
}
