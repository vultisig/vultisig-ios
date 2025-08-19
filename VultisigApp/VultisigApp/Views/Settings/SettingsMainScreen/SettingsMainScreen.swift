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
                .education,
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
        Screen(title: "settings".localized) {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(groups) { group in
                        groupView(for: group)
                    }
                    appVersion
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                    EditVaultView(vault: vault)
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
            case .referralCode:
                ReferralView()
            case .faq:
                SettingsFAQView()
            case .education:
                // TODO: - Check
                EmptyView()
            case .checkForUpdates:
                checkUpdateView
            default:
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $showAdvancedSettings) {
            SettingsAdvancedView()
        }
    }
    
    func groupView(for group: SettingsOptionGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textExtraLight)
            
            SettingsSectionContainerView {
                VStack(spacing: .zero) {
                    ForEach(group.options, id: \.self) { option in
                        optionView(for: option, shouldHighlight: option == .registerVaults)
                        GradientListSeparator()
                            .showIf(option != group.options.last)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    func optionView(for option: SettingsOption, shouldHighlight: Bool) -> some View {
        let bgColor: Color? = shouldHighlight ? Theme.colors.primaryAccent3 : nil
        let iconColor: Color = shouldHighlight ? Theme.colors.textPrimary : Theme.colors.primaryAccent4
        
        optionContainerView(for: option) {
            HStack(spacing: 12) {
                if let icon = option.icon {
                    Icon(named: icon, color: iconColor, size: 20)
                }
                
                Text(option.title.localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textPrimary)
                
                Spacer()
                
                if let description = description(for: option) {
                    Text(description)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                
                Icon(
                    named: "chevron-right",
                    color: Theme.colors.textExtraLight,
                    size: 16
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(bgColor)
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
        #if os(macOS)
            MacCheckUpdateView()
        #else
            PhoneCheckUpdateView()
        #endif
    }
}

#Preview {
    SettingsMainScreen()
        .environmentObject(SettingsViewModel())
        .environmentObject(HomeViewModel())
}
