//
//  RegisterVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

import SwiftUI

struct RegisterVaultView: View {
    
    var body: some View {
        ZStack {
            Background()
            view
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
    
    var button: some View {
        FilledButton(title: "saveQRCode")
    }
}

#Preview {
    RegisterVaultView()
}
