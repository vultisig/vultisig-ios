//
//  BackupVaultNowView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-05.
//

import SwiftUI

struct BackupVaultNowView: View {
    let vault: Vault

    @State var isWarningShown = false
    @State var isHomeAfterSkipShown = false

    var body: some View {
        ZStack {
            Background()
            view
            shadowView
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var view: some View {
        container
            .navigationDestination(isPresented: $isHomeAfterSkipShown) {
                HomeView(selectedVault: vault, showVaultsList: false, shouldJoinKeygen: false)
            }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(width: 44)
                Spacer()
                logo
                Spacer()
                skipButton.frame(width: 44)
            }
            image
            title
            Spacer()
            disclaimer
            Spacer()
            description
            Spacer()
            backupButton
        }
        .font(.body12Montserrat)
        .foregroundColor(.neutral0)
        .multilineTextAlignment(.center)
    }

    var shadowView: some View {
        Background()
            .opacity(isWarningShown ? 0.5 : 0)
            .animation(.default, value: isWarningShown)
    }

    var logo: some View {
        Image("LogoWithTitle")
            .padding(.top, 30)
    }

    var title: some View {
        Text(NSLocalizedString("backupNowTitle", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body24MontserratMedium)
            .fixedSize(horizontal: false, vertical: true)
    }

    var image: some View {
        Image("BackupNowImage")
            .offset(x: 5)
            .padding(.bottom, 6)
    }

    var disclaimer: some View {
        WarningView(text: NSLocalizedString("backupNowWarning", comment: ""))
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
    }

    var description: some View {
        Text(NSLocalizedString("backupNowSubtitle", comment: ""))
            .padding(.horizontal, 32)
            .multilineTextAlignment(.center)
    }
    
    var backupButton: some View {
        NavigationLink {
            BackupPasswordSetupView(vault: vault, isNewVault: true)
        } label: {
            FilledButton(title: "Backup")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }
    
    var skipButton: some View {
        Button {
            isWarningShown = true
        } label: {
            Image("x")
        }
        .buttonStyle(.plain)
        .padding(16)
        .sheet(isPresented: $isWarningShown) {
            BackupVaultWarningView(isPresented: $isWarningShown, isSkipPressed: $isHomeAfterSkipShown)
                .presentationDetents([.height(256)])
        }
    }
}

#Preview {
    BackupVaultNowView(vault: Vault.example)
}
