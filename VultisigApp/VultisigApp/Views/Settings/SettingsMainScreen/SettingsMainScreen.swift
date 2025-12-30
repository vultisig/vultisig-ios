//
//  SettingsMainScreen.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-05.
//

import SwiftUI

struct SettingsMainScreen: View {
    @Environment(\.router) var router
    @ObservedObject var vault: Vault
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    @StateObject var referredViewModel = ReferredViewModel()
    @StateObject var referralViewModel = ReferralViewModel()

    @State var tapCount = 0
    @State var scale: CGFloat = 1
    @State var showVaultDetailQRCode: Bool = false
    @State var showReferralBannerSheet = false

    let groups: [SettingsOptionGroup] = [
        SettingsOptionGroup(
            title: "vault",
            options: [
                .vaultSettings,
                .vultDiscountTiers,
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
                ToolbarButton(image: "qr-code") {
                    router.navigate(to: SettingsRoute.vaultDetailQRCode(vault: vault))
                }
            }
        }
        .crossPlatformSheet(isPresented: $showReferralBannerSheet) {
            ReferralOnboardingBanner {
                showReferralBannerSheet = false
                referredViewModel.showReferralCodeOnboarding = false
                router.navigate(to: ReferralRoute.onboarding)
            } onClose: {
                showReferralBannerSheet = false
            }.presentationDetents([.height(400)])
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
                navigateToOption(option)
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

    func navigateToOption(_ option: SettingsOption) {
        switch option {
        case .vaultSettings:
            router.navigate(to: SettingsRoute.vaultSettings(vault: vault))
        case .vultDiscountTiers:
            router.navigate(to: SettingsRoute.vultDiscountTiers(vault: vault))
        case .registerVaults:
            router.navigate(to: SettingsRoute.registerVaults(vault: vault))
        case .language:
            router.navigate(to: SettingsRoute.language)
        case .currency:
            router.navigate(to: SettingsRoute.currency)
        case .addressBook:
            router.navigate(to: SettingsRoute.addressBook)
        case .faq:
            router.navigate(to: SettingsRoute.faq)
        case .checkForUpdates:
            router.navigate(to: SettingsRoute.checkForUpdates)
        default:
            break
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
            .foregroundColor(Theme.colors.textTertiary)
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
                router.navigate(to: SettingsRoute.advancedSettings)
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
                showReferralBannerSheet = true
            } else {
                router.navigate(to: ReferralRoute.initial)
            }
        default:
            return
        }
    }
}

#Preview {
    SettingsMainScreen(vault: .example)
        .environmentObject(SettingsViewModel())
}
