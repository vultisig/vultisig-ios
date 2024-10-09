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
        .navigationTitle(NSLocalizedString("registerVault", comment: ""))
    }
    
    var view: some View {
        VStack {
            image
            content
        }
    }
    
    var image: some View {
        VultisigLogo(showTexts: false)
            .padding(.vertical, 30)
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 36) {
            text1
            text2
            text3
            text4
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body20MenloBold)
        .foregroundColor(.neutral0)
        .padding(16)
    }
    
    var text1: some View {
        Text(NSLocalizedString("registerVaultText1", comment: ""))
    }
    
    var text2: some View {
        HStack {
            Text(NSLocalizedString("registerVaultText2", comment: ""))
            button
        }
    }
    
    var text3: some View {
        Text(NSLocalizedString("registerVaultText3", comment: ""))
    }
    
    var text4: some View {
        Text(NSLocalizedString("registerVaultText4", comment: ""))
    }
    
    var button: some View {
        Link(destination: StaticURL.VultisigWeb) {
            label
        }
    }
    
    var label: some View {
        Text("Vultisig Web")
            .foregroundColor(.turquoise600)
            .padding(.vertical, 12)
            .padding(.horizontal, 28)
            .background(Color.blue600)
            .cornerRadius(10)
    }
}

#Preview {
    RegisterVaultView()
}
