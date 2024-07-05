//
//  BackupNowDisclaimer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupNowDisclaimer: View {
    let vault: Vault
    
    var body: some View {
        NavigationLink {
            BackupPasswordSetupView(vault: vault)
        } label: {
            content
        }
    }
    
    var content: some View {
        HStack {
            icon
            Spacer()
            title
            Spacer()
            chevron
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color.backupNowRed.opacity(0.3))
        .cornerRadius(12)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.backupNowRed, lineWidth: 1)
        )
    }
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.body24MontserratMedium)
            .foregroundColor(.backupNowRed)
    }
    
    var title: some View {
        Text("Backup your vault now!")
            .font(.body16MontserratMedium)
            .foregroundColor(.neutral0)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.body12MenloMedium)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    BackupNowDisclaimer()
}
