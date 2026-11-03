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

    @State var tapCount = 0
    @State var scale: CGFloat = 1

    private static let contentTopInset: CGFloat = 3

    let vaultGroup = SettingsOptionGroup(title: "vault", options: [.vaultSettings, .vultDiscountTiers])
    let communityLinks: [SettingsOption] = [.twitter, .discord, .github, .website]
    let communityGroup = SettingsOptionGroup(title: "vultisigCommunity", options: [.rateApp, .shareApp])
    let supportGroup = SettingsOptionGroup(title: "support", options: [.faq, .checkForUpdates, .education])
    let legalGroup = SettingsOptionGroup(title: "legal", options: [.privacyPolicy, .termsOfService])

    var generalGroup: SettingsOptionGroup {
        var options: [SettingsOption] = [.notifications, .language, .currency, .homeDisplay]
        #if os(iOS)
        options.append(.widgetWatchlist)
        #endif
        options.append(.addressBook)
        return SettingsOptionGroup(title: "general", options: options)
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    groupView(for: vaultGroup)
                    groupView(for: generalGroup)
                    communitySection
                    groupView(for: supportGroup)
                    groupView(for: legalGroup)
                    appVersion
                        .padding(.bottom, 12)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Settings.container)
        .screenTitle("settings".localized)
        .screenEdgeInsets(ScreenEdgeInsets(top: Self.contentTopInset, bottom: 0))
    }

    func groupView(for group: SettingsOptionGroup) -> some View {
        SettingsSectionView(title: group.title.localized, style: .flush) {
            rows(for: group)
        }
    }

    func rows(for group: SettingsOptionGroup) -> some View {
        ForEach(Array(group.options.enumerated()), id: \.element) { index, option in
            optionView(for: option)
                .commonListItemContainer(index: index, itemsCount: group.options.count, style: .flush)
        }
    }

    /// Link tiles above a card of rows, which `SettingsSectionView` cannot lay out.
    var communitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(communityGroup.title.localized)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textTertiary)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(communityLinks) { option in
                        optionContainerView(for: option) {
                            SettingsCommunityTile(icon: option.icon, title: option.title.localized)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: .zero) {
                    rows(for: communityGroup)
                }
                .commonListContainer(style: .flush)
            }
        }
    }

    @ViewBuilder
    func optionView(for option: SettingsOption) -> some View {
        optionContainerView(for: option) {
            SettingsCommonOptionView(
                icon: option.icon,
                title: option.title.localized,
                description: description(for: option),
                chevron: option.chevron
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
        case .homeDisplay:
            router.navigate(to: SettingsRoute.homeDisplay)
        case .widgetWatchlist:
            router.navigate(to: SettingsRoute.widgetWatchlist)
        case .notifications:
            router.navigate(to: SettingsRoute.notifications)
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
            return settingsViewModel.selectedLanguage.nativeName
        case .currency:
            return settingsViewModel.selectedCurrency.rawValue
        default:
            return nil
        }
    }

    var appVersion: some View {
        Text(Bundle.main.appVersionString)
            .settingsText(.caption)
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
}

#Preview {
    SettingsMainScreen(vault: .example)
        .environmentObject(SettingsViewModel())
}
