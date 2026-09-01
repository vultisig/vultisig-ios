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

    var passcodeService: PasscodeService = .shared

    /// Mirrors `PasscodeService.isSet`, which is actor-isolated and so cannot be
    /// read from `body`. Refreshed on appear, the same way `ManagePasscodeScreen`
    /// does it.
    @State private var passcodeIsSet = false

    @State var tapCount = 0
    @State var scale: CGFloat = 1
    @State var showReferralBannerSheet = false

    var groups: [SettingsOptionGroup] {
        var generalOptions: [SettingsOption] = [
            .notifications,
            .referralCode,
            .language,
            .currency
        ]

        #if os(iOS)
        generalOptions.append(.widgetWatchlist)
        #endif
        generalOptions.append(.addressBook)

        // Hidden until a tester opts in from Settings → Advanced, so merging
        // this layer does not put the feature in front of anyone. Shown anyway
        // once a passcode exists, otherwise turning the flag back off would
        // strand someone inside a passcode with no screen left to disable it.
        let securityGroups: [SettingsOptionGroup] =
            settingsViewModel.passcodeFeatureEnabled || passcodeIsSet
            ? [SettingsOptionGroup(title: "security", options: [.managePasscode])]
            : []

        return [
            SettingsOptionGroup(
                title: "vault",
                options: [
                    .vaultSettings,
                    .vultDiscountTiers
                ]
            ),
            SettingsOptionGroup(
                title: "general",
                options: generalOptions
            )
        ]
        + securityGroups
        + [
        SettingsOptionGroup(
            title: "support",
            options: [
                .faq,
                .checkForUpdates,
                .education,
                .rateApp,
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
    }

    var body: some View {
        Screen {
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
        .task { passcodeIsSet = await passcodeService.isSet }
        .accessibilityIdentifier(AccessibilityID.Settings.container)
        .screenTitle("settings".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
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
            ForEach(Array(group.options.enumerated()), id: \.element) { index, option in
                optionView(for: option, shouldHighlight: false)
                    .commonListItemContainer(index: index, itemsCount: group.options.count)
            }
        }
    }

    @ViewBuilder
    func optionView(for option: SettingsOption, shouldHighlight: Bool) -> some View {
        optionContainerView(for: option) {
            SettingsCommonOptionView(
                icon: option.icon,
                title: option.title.localized,
                description: description(for: option),
                type: shouldHighlight ? .highlighted : .normal
            )
        }
        .accessibilityIdentifier(option.accessibilityID ?? "")
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
        case .language:
            router.navigate(to: SettingsRoute.language)
        case .currency:
            router.navigate(to: SettingsRoute.currency)
        case .widgetWatchlist:
            router.navigate(to: SettingsRoute.widgetWatchlist)
        case .notifications:
            router.navigate(to: SettingsRoute.notifications)
        case .addressBook:
            router.navigate(to: SettingsRoute.addressBook)
        case .managePasscode:
            router.navigate(to: SettingsRoute.managePasscode)
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
            .foregroundStyle(Theme.colors.textTertiary)
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
