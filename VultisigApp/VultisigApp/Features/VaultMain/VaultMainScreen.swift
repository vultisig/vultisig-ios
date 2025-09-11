//
//  VaultMainScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 09/09/2025.
//

import SwiftUI

struct VaultMainScreen: View {
    let vault: Vault
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 32) {
                        VaultMainBalanceView(vault: vault)
                        CoinActionsView(
                            actions: homeViewModel.vaultActions,
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
                    
                    Separator()
                }
                .padding(.horizontal, 16)
            }
            .safeAreaInset(edge: .top) {
                Spacer()
                    .frame(height: 78)
            }
//            .padding(.top, 78)
            
            VaultMainHeaderView(
                vault: vault,
                vaultSelectorAction: onVaultSelector,
                settingsAction: onSettings
            )
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(VaultMainScreenBackground())
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
}

#Preview {
    VaultMainScreen(vault: .example)
        .environmentObject(HomeViewModel())
}
