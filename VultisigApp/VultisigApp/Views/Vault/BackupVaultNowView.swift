//
//  BackupVaultNowView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupNowTestView: View {
    
    
    var body: some View {
        ZStack {
            Background()
            view
        }
    }
    
    var view: some View {
        VStack(spacing: 36) {
            title
            image
            disclaimer
            description
            Spacer()
            buttons
        }
        .font(.body14Menlo)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
    }
    
    var title: some View {
        Image("LogoWithTitle")
            .padding(.top, 30)
    }
    
    var image: some View {
        Image("BackupNowImage")
    }
    
    var disclaimer: some View {
        Text("Please Backup your Vault Shares now.")
            .padding(.horizontal, 80)
    }
    
    var description: some View {
        Text("Note: Never store Vault Shares from different devices in the same location")
            .padding(.horizontal, 60)
    }
    
    var buttons: some View {
        VStack {
            backupButton
            skipButton
        }
    }
    
    var backupButton: some View {
        Button {
            
        } label: {
            FilledButton(title: "Backup")
        }
    }
    
    var skipButton: some View {
        Button {
            
        } label: {
            Text(NSLocalizedString("skip", comment: ""))
                .padding(12)
                .frame(maxWidth: .infinity)
                .foregroundColor(Color.turquoise600)
                .font(.body16MontserratMedium)
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
    }
}

#Preview {
    BackupNowTestView()
}
