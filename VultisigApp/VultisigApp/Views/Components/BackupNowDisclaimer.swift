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
        ZStack {
            content
            navigationCell.opacity(0)
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(1)
    }
    
    var navigationCell: some View {
        NavigationLink {
            BackupPasswordSetupView(vault: vault)
        } label: {
            content
        }
    }
    
    var content: some View {
        ZStack {
            title
            components
        }
        .frame(height: 76)
        .padding(.horizontal, 12)
        .background(Color.alertRed.opacity(0.3))
        .cornerRadius(12)
        .overlay (
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.alertRed, lineWidth: 1)
        )
    }
    
    var components: some View {
        HStack {
            icon
            Spacer()
            chevron
        }
    }
    
    var icon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.body24MontserratMedium)
            .foregroundColor(.alertRed)
    }
    
    var title: some View {
        Text(NSLocalizedString("backupYourVaultNow", comment: ""))
            .font(.body16MontserratSemiBold)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
    
    var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.body12MenloMedium)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    BackupNowDisclaimer(vault: Vault.example)
}
