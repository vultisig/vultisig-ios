//
//  TronDashboardView+iOS.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

#if os(iOS)
extension TronDashboardView {
    var content: some View {
        ZStack {
            VaultMainScreenBackground()
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: TronConstants.Design.verticalSpacing) {
                        topBanner
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("tronDashboardStaking", comment: "Staking"))
                                .font(.headline)
                                .foregroundStyle(Theme.colors.textPrimary)
                            
                            Text(NSLocalizedString("tronDashboardStakingDescription", comment: "Freeze your TRX to gain bandwidth and energy for free transactions."))
                                .font(.body)
                                .foregroundStyle(Theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        InfoBannerView(
                            description: NSLocalizedString("tronDashboardInfoText", comment: "Frozen TRX provides bandwidth and energy resources..."),
                            type: .info,
                            leadingIcon: nil,
                            onClose: {
                                withAnimation { appClosedBanners.append(tronDashboardBannerId) }
                            }
                        )
                        .showIf(showInfoBanner)
                        
                        if let error = model.error, error.localizedDescription.lowercased() != "cancelled" {
                            InfoBannerView(
                                description: error.localizedDescription,
                                type: .error,
                                leadingIcon: nil,
                                onClose: {
                                    withAnimation { model.error = nil }
                                }
                            )
                        }
                        
                        frozenBalanceCard
                        
                        pendingWithdrawalsCard
                    }
                    .padding(.top, TronConstants.Design.mainViewTopPadding)
                    .padding(.bottom, TronConstants.Design.mainViewBottomPadding)
                    .padding(.horizontal, TronConstants.Design.horizontalPadding)
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .onAppear {
            Task { await loadData() }
        }
    }
}
#endif
