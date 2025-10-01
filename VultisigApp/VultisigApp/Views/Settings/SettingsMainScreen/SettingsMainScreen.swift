//
//  SettingsMainScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsMainScreen: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()
    
    @State var tapCount = 0
    @State var scale: CGFloat = 1
    @State var showAdvancedSettings: Bool = false
    
    @State var selectedOption: SettingsOption?

    let groups: [SettingsOptionGroup] = [
        SettingsOptionGroup(
            title: "vault",
            options: [
                .vaultSettings,
                .registerVaults
            ]
        ),
        SettingsOptionGroup(
            title: "general",
            options: [
                .language,
                .currency,
                .addressBook,
                .referralCode
            ]
        ),
        SettingsOptionGroup(
            title: "support",
            options: [
                .faq,
                // TODO: - Unused for now
                // .education,
                .checkForUpdates,
                .shareApp
            ]
        ),
        SettingsOptionGroup(
            title: "vultisigCommunity",
            options: [
                .twitter,
                .discord,
                .github,
                .vult,
                .website
            ]
        ),
        SettingsOptionGroup(
            title: "legal",
            options: [
                .privacyPolicy,
                .termsOfService
            ]
        )
    ]
    
    var body: some View {
        Screen(showNavigationBar: false, edgeInsets: ScreenEdgeInsets(bottom: 0)) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { group in
                        groupView(for: group)
                    }
                    appVersion
                        .padding(.bottom, 12)
                }
            }
        }
        .crossPlatformToolbar("settings".localized) {
            CustomToolbarItem(placement: .trailing) {
                NavigationLink {
                    if let vault = homeViewModel.selectedVault {
                        VaultDetailQRCodeView(vault: vault)
                    }
                } label: {
                    NavigationQRCodeButton()
                }
            }
        }
        .navigationDestination(item: $selectedOption) { option in
            switch option {
            case .vaultSettings:
                if let vault = homeViewModel.selectedVault {
                    VaultSettingsScreen(vault: vault)
                } else {
                    ErrorMessage(text: "errorFetchingVault")
                }
            case .registerVaults:
                if let vault = homeViewModel.selectedVault {
                    RegisterVaultView(vault: vault)
                } else {
                    ErrorMessage(text: "errorFetchingVault")
                }
            case .language:
                SettingsLanguageSelectionView()
            case .currency:
                SettingsCurrencySelectionView()
            case .addressBook:
                AddressBookView(
                    shouldReturnAddress: false,
                    returnAddress: .constant("")
                )
            case .faq:
                SettingsFAQView()
            case .checkForUpdates:
                checkUpdateView
            default:
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $showAdvancedSettings) {
            SettingsAdvancedView()
        }
        .navigationDestination(isPresented: $referredViewModel.navigationToReferralOverview) {
            ReferredOnboardingView(referredViewModel: referredViewModel)
        }
        .navigationDestination(isPresented: $referredViewModel.navigationToReferralsView) {
            referralView
        }
        .sheet(isPresented: $referredViewModel.showReferralBannerSheet) {
            referralOverviewSheet
        }
    }
    
    func groupView(for group: SettingsOptionGroup) -> some View {
        SettingsSectionView(title: group.title.localized) {
            ForEach(group.options, id: \.self) { option in
                optionView(
                    for: option,
                    shouldHighlight: option == .registerVaults,
                    showSeparator: option != group.options.last
                )
            }
        }
    }
    
    @ViewBuilder
    func optionView(for option: SettingsOption, shouldHighlight: Bool, showSeparator: Bool) -> some View {
        optionContainerView(for: option) {
            SettingsCommonOptionView(
                icon: option.icon,
                title: option.title.localized,
                description: description(for: option),
                type: shouldHighlight ? .highlighted : .normal,
                showSeparator: showSeparator
            )
        }
    }
    
    @ViewBuilder
    func optionContainerView<Content: View>(for option: SettingsOption, content: () -> Content) -> some View {
        switch option.type {
        case .navigation:
            Button {
                selectedOption = option
            } label: {
                content()
            }
        case .button:
            Button {
                onOption(option)
            } label: {
                content()
            }
        case .link(let url):
            Link(destination: url, label: content)
        case .shareLink(let url):
            ShareLink(item: url, label: content)
        }
    }
    
    func description(for option: SettingsOption) -> String? {
        switch option {
        case .language:
            return settingsViewModel.selectedLanguage.rawValue
        case .currency:
            return settingsViewModel.selectedCurrency.rawValue
        default:
            return nil
        }
    }
    
    var appVersion: some View {
        Text(Bundle.main.appVersionString)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textExtraLight)
            .scaleEffect(scale)
            .onTapGesture {
                handleVersionTap()
            }
    }
    
    private func handleVersionTap() {
        tapCount += 1
        
        withAnimation(.spring(duration: 0.1)) {
            scale = 1.1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut) {
                scale = 1.0
            }
            
            if tapCount > 4 {
                tapCount = 0
                showAdvancedSettings = true
            }
        }
    }
    
    var checkUpdateView: some View {
            PhoneCheckUpdateView()
    }
    
    func onOption(_ option: SettingsOption) {
        switch option {
        case .referralCode:
            if referredViewModel.showReferralCodeOnboarding {
                referredViewModel.showReferralBannerSheet = true
            } else {
                referredViewModel.navigationToReferralsView = true
            }
        default:
            return
        }
    }
    
    var referralOverviewSheet: some View {
        ReferralOnboardingBanner(referredViewModel: referredViewModel)
            .presentationDetents([.height(400)])
    }
    
    @ViewBuilder
    var referralView: some View {
        ReferralLaunchView(
            referredViewModel: referredViewModel,
            referralViewModel: referralViewModel
        )
    }
}

#Preview {
    SettingsMainScreen()
        .environmentObject(SettingsViewModel())
        .environmentObject(HomeViewModel())
}
