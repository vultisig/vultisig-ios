//
//  SettingsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State var tapCount = 0
    @State var scale: CGFloat = 1
    @State var showAdvancedSettings: Bool = false
    
    @StateObject var referralViewModel = ReferralViewModel()
    
    var body: some View {
        content
            .navigationDestination(isPresented: $showAdvancedSettings) {
                SettingsAdvancedView()
            }
            .navigationDestination(isPresented: $referralViewModel.navigationToReferralOverview, destination: {
                ReferralOnboardingView(referralViewModel: referralViewModel)
            })
            .navigationDestination(isPresented: $referralViewModel.navigationToCreateReferralView, destination: {
                ReferralLaunchView(referralViewModel: referralViewModel)
            })
            .sheet(isPresented: $referralViewModel.showReferralBannerSheet) {
                referralOverviewSheet
            }
    }
    
    var mainSection: some View {
        VStack(spacing: 16) {
            vaultSettingsCell
            languageSelectionCell
            currencySelectionCell
            addressBookCell
            defaultChainsSelectionCell
            referralCodeCell
            faqCell
        }
    }
    
    var otherSection: some View {
        VStack(spacing: 16) {
            getTitle("other")
            registerVaultCell
            checkUpdateCell
            shareAppCell
        }
    }
    
    var legalSection: some View {
        VStack(spacing: 16) {
            getTitle("legal")
            privacyPolicyCell
            termsOfServiceCell
        }
    }
    
    var bottomSection: some View {
        VStack(spacing: 24) {
            socials
            appVersion
        }
        .padding(.bottom, 30)
        .padding(.top, 100)
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

    var defaultChainsSelectionCell: some View {
        NavigationLink {
            SettingsDefaultChainView()
        } label: {
            SettingCell(title: "defaultChains", icon: "circle.hexagonpath")
        }
    }

    var addressBookCell: some View {
        NavigationLink {
            AddressBookView(
                shouldReturnAddress: false,
                returnAddress: .constant("")
            )
        } label: {
            SettingCell(title: "addressBook", icon: "text.book.closed")
        }
    }
    
    var referralCodeCell: some View {
        ZStack {
            if referralViewModel.showReferralCodeOnboarding {
                referralCodeButton
            } else {
                referralCodeNavigationLink
            }
        }
    }
    
    var referralCodeNavigationLink: some View {
        NavigationLink {
            ReferralLaunchView(referralViewModel: referralViewModel)
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeButton: some View {
        Button {
            referralViewModel.showReferralBannerSheet = true
        } label: {
            referralCodeLabel
        }
    }
    
    var referralCodeLabel: some View {
        SettingCell(title: "referralCode", icon: "horn")
    }
    
    var faqCell: some View {
        NavigationLink {
            SettingsFAQView()
        } label: {
            SettingCell(title: "faq", icon: "questionmark.circle")
        }
    }
    
    var registerVaultCell: some View {
        NavigationLink {
            if let vault = homeViewModel.selectedVault {
                RegisterVaultView(vault: vault)
            } else {
                ErrorMessage(text: "errorFetchingVault")
            }
        } label: {
            SettingVaultRegistrationCell()
        }
    }
    
    var checkUpdateCell: some View {
        NavigationLink {
            checkUpdateView
        } label: {
            SettingCell(title: "checkForUpdate", icon: "arrow.down.circle.dotted")
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
    
    var privacyPolicyCell: some View {
        Link(destination: StaticURL.PrivacyPolicyURL) {
            SettingCell(title: "privacyPolicy", icon: "checkmark.shield")
        }
    }
    
    var termsOfServiceCell: some View {
        Link(destination: StaticURL.TermsOfServiceURL) {
            SettingCell(title: "termsOfService", icon: "doc.text")
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
        .scaleEffect(scale)
        .onTapGesture {
            handleVersionTap()
        }
    }
    
    var referralOverviewSheet: some View {
        ReferralOnboardingBanner(referralViewModel: referralViewModel)
            .presentationDetents([.height(400)])
    }
    
    private func handleVersionTap() {
        tapCount += 1
        
        withAnimation(.spring(duration: 0.1)) {
            scale = 1.1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(duration: 0.1)) {
                scale = 1
            }
            
            if tapCount > 4 {
                tapCount = 0
                showAdvancedSettings = true
            }
        }
    }
    
    private func getTitle(_ title: String) -> some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body14MontserratMedium)
            .foregroundColor(.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(HomeViewModel())
}
