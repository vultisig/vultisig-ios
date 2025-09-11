//
//  VaultMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainScreen: View {
    @ObservedObject var vault: Vault
    
    @StateObject var viewModel = VaultMainViewModel()
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    @State private var showCopyNotification = false
    @State private var copyNotificationText = ""
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    topContentSection
                    Separator(color: Theme.colors.borderLight, opacity: 1)
                    bottomContentSection
                }
                .padding(.horizontal, 16)
            }
            .safeAreaInset(edge: .top) {
                Spacer()
                    .frame(height: 78)
            }
            
            header
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VaultMainScreenBackground())
        .overlay(
            NotificationBannerView(
                text: copyNotificationText,
                isVisible: $showCopyNotification
            ).showIf(showCopyNotification)
            .zIndex(2)
        )
    }
    
    var header: some View {
        VaultMainHeaderView(
            vault: vault,
            vaultSelectorAction: onVaultSelector,
            settingsAction: onSettings
        )
        .padding(.horizontal, 16)
    }
    
    var topContentSection: some View {
        VStack(spacing: 32) {
            VaultMainBalanceView(vault: vault)
            CoinActionsView(
                actions: viewModel.availableActions,
                onAction: onAction
            )
            VaultBannerView(
                title: "signFasterThanEverBefore".localized,
                subtitle: "upgradeYourVaultNow".localized,
                buttonTitle: "upgradeNow".localized,
                bgImage: "referral-banner-2",
                action: onBannerAction,
                onClose: onBannerClose
            )
        }
    }
    
    var bottomContentSection: some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: 8) {
                SegmentedControl(
                    selection: $viewModel.selectedTab,
                    items: viewModel.tabs
                )
                Spacer()
                CircularAccessoryIconButton(icon: "magnifying-glass", action: onSearch)
                CircularAccessoryIconButton(icon: "write", action: onManageChains)
            }
            .padding(.bottom, 16)
            VaultMainChainListView(
                vault: vault,
                onCopy: onCopy,
                onAction: onChainAction
            )
        }
    }
    
    func onVaultSelector() {
        // TODO: - Add vault selector in upcoming PRs
    }
    
    func onSettings() {
        // TODO: - Add settings in upcoming PRs
    }
    
    func onAction(_ action: CoinAction) {
        // TODO: - Add action in upcoming PRs
    }
    
    func onBannerAction() {
        
    }
    
    func onBannerClose() {
        
    }
    
    func onSearch() {
        
    }
    
    func onManageChains() {
        
    }
    
    func onCopy(_ group: GroupedChain) {
        ClipboardManager.copyToClipboard(group.address)
        
        copyNotificationText = String(format: "coinAddressCopied".localized, group.name)
        showCopyNotification = true
    }
    
    func onChainAction(_ group: GroupedChain) {
        
    }
}

#Preview {
    VaultMainScreen(vault: .example)
        .environmentObject(HomeViewModel())
        .environmentObject(VaultDetailViewModel())
}
