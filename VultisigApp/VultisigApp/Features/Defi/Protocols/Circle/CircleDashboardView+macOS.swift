//
//  CircleDashboardView+macOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-11.
//

import SwiftUI

#if os(macOS)
extension CircleDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    topBanner
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("circleDashboardDeposited", comment: "Deposited"))
                            .font(.headline)
                            .foregroundStyle(Theme.colors.textPrimary)
                        
                        Text(NSLocalizedString("circleDashboardDepositDescription", comment: "Deposit your $USDC..."))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    if showInfoBanner {
                         InfoBannerView(
                            description: NSLocalizedString("circleDashboardInfoText", comment: "Funds remain..."),
                            type: .info,
                            leadingIcon: "info.circle",
                            onClose: {
                                withAnimation { showInfoBanner = false }
                            }
                        )
                        .padding(.horizontal, 16)
                    }
                    
                    usdcDepositedCard
                    
                    if !model.apy.isEmpty {
                        yieldDetailsCard
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .onAppear {
            Task { await loadData() }
        }
        .sheet(isPresented: $showDeposit) {
            CircleDepositView(vault: vault)
                .presentationSizingFitted()
                .applySheetSize(700, nil)
                .background(Theme.colors.bgPrimary)
        }
        .sheet(isPresented: $showWithdraw) {
            CircleWithdrawView(vault: vault, model: model)
                .presentationSizingFitted()
                .applySheetSize(700, nil)
                .background(Theme.colors.bgPrimary)
        }
        .navigationTitle(NSLocalizedString("circleTitle", comment: "Circle"))
        .toolbar {
             ToolbarItem(placement: .navigation) {
                 NavigationBackButton()
             }
        }
    }
}
#endif
