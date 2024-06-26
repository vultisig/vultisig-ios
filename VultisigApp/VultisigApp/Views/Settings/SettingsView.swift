//
//  SettingsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsView: View {
    @Binding var showMenu: Bool
    @ObservedObject var homeViewModel: HomeViewModel
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("settings", comment: "Settings"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showMenu)
            }
        }

    }
    
    var view: some View {
        VStack(spacing: 24) {
            mainSection
            otherSection
            Spacer()
            socials
            appVersion
        }
        .padding(15)
        .padding(.top, 30)
    }
    
    var mainSection: some View {
        VStack(spacing: 16) {
            vaultSettingsCell
            languageSelectionCell
            currencySelectionCell
            faqCell
        }
    }
    
    var otherSection: some View {
        VStack(spacing: 16) {
            getTitle("other")
            shareAppCell
        }
    }
    
    var vaultSettingsCell: some View {
        NavigationLink {
            if let vault = homeViewModel.selectedVault {
                EditVaultView(vault: vault)
            } else {
                ErrorMessage(text: "errorFetchingVault")
            }
        } label: {
            SettingCell(title: "vaultSettings", icon: "gear")
        }
    }
    
    var languageSelectionCell: some View {
        NavigationLink {
            SettingsLanguageSelectionView()
        } label: {
            SettingCell(title: "language", icon: "globe", selection: settingsViewModel.selectedLanguage.rawValue)
        }
    }
    
    var currencySelectionCell: some View {
        NavigationLink {
            SettingsCurrencySelectionView()
        } label: {
            SettingCell(title: "currency", icon: "dollarsign.circle", selection: SettingsCurrency.current.rawValue)
        }
    }
    
    var faqCell: some View {
        NavigationLink {
            SettingsFAQView()
        } label: {
            SettingCell(title: "faq", icon: "questionmark.circle")
        }
    }
    
    var shareAppCell: some View {
        ShareLink(item: StaticURL.AppStoreVultisigURL) {
            SettingCell(title: "shareTheApp", icon: "square.and.arrow.up")
        }
    }
    
    var socials: some View {
        HStack(spacing: 32) {
            githubButton
            xButton
            discordButton
        }
        .padding(.top, 100)
    }
    
    var githubButton: some View {
        Link(destination: StaticURL.GithubVultisigURL) {
            Image("GithubLogo")
        }
    }
    
    var xButton: some View {
        Link(destination: StaticURL.XVultisigURL) {
            Image("xLogo")
        }
    }
    
    var discordButton: some View {
        Link(destination: StaticURL.DiscordVultisigURL) {
            Image("DiscordLogo")
        }
    }
    
    var appVersion: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        return VStack {
            Text("Vultisig APP V\(version ?? "1")")
            Text("(Build \(build ?? "1"))")
        }
        .textCase(.uppercase)
        .font(.body14Menlo)
        .foregroundColor(.turquoise600)
    }
    
    private func getTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView(showMenu: .constant(true), homeViewModel: HomeViewModel())
        .environmentObject(SettingsViewModel())
}
