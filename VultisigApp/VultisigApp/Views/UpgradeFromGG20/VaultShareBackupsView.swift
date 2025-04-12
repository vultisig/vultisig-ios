//
//  VaultShareBackupsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

struct VaultShareBackupsView: View {
    var body: some View {
        ZStack {
            Background()
            content
        }
    }
    
    var image: some View {
        Image("VaultShareBackupsImage")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 512, maxHeight: 512)
            .scaleEffect(1.1)
            .padding(-36)
    }
    
    var description: some View {
        Group {
            Text(NSLocalizedString("vaultShareBackupsViewTitle1", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("vaultShareBackupsViewTitle2", comment: ""))
                .foregroundColor(.neutral0)
        }
        .multilineTextAlignment(.center)
        .font(.body28BrockmannMedium)
    }
    
    var button: some View {
        Button {
            
        } label: {
            label
        }
        .padding(.vertical, 36)
    }
    
    var label: some View {
        FilledButton(title: "next")
            .frame(width: 100)
    }
}

#Preview {
    VaultShareBackupsView()
}
